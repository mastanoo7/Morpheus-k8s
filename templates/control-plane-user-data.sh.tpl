#!/usr/bin/env bash
set -euo pipefail

exec > >(tee -a /var/log/kubeadm-bootstrap.log) 2>&1
trap 'rc=$?; echo "ERROR: control-plane bootstrap failed at line $LINENO (exit $rc)" >&2; exit $rc' ERR
export DEBIAN_FRONTEND=noninteractive

retry() {
  local max="$1"; shift
  local attempt=1
  until "$@"; do
    if (( attempt >= max )); then
      echo "ERROR: command failed after $attempt attempts: $1" >&2
      return 1
    fi
    sleep $((attempt * 10))
    attempt=$((attempt + 1))
  done
}

echo "Waiting for DNS and Internet connectivity"
retry 18 getent hosts pkgs.k8s.io
retry 18 curl -fsSI --max-time 15 https://pkgs.k8s.io/
retry 12 curl -fsSI --max-time 15 https://registry.k8s.io/v2/
retry 12 curl -fsSI --max-time 15 https://raw.githubusercontent.com/

retry 5 apt-get update
retry 5 apt-get install -y apt-transport-https ca-certificates curl gpg unzip containerd

cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system
swapoff -a
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -ri 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml
systemctl enable --now containerd

install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${kubernetes_minor_version}/deb/Release.key" |
  gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${kubernetes_minor_version}/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list
retry 5 apt-get update
retry 5 apt-get install -y \
  "kubelet=${kubernetes_version}-1.1" \
  "kubeadm=${kubernetes_version}-1.1" \
  "kubectl=${kubernetes_version}-1.1"
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
fi
retry 10 aws sts get-caller-identity --region "${aws_region}" --output text >/dev/null

TOKEN="$(curl -fsS -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' http://169.254.169.254/latest/api/token)"
PRIVATE_IP="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)"
PRIVATE_DNS="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-hostname)"
PUBLIC_IP="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)"
PUBLIC_DNS="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-hostname)"
unset TOKEN

if [[ ! -f /etc/kubernetes/admin.conf ]]; then
  cat >/etc/kubernetes-kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "$PRIVATE_IP"
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
  - name: node-ip
    value: "$PRIVATE_IP"
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: "${cluster_name}"
kubernetesVersion: "v${kubernetes_version}"
controlPlaneEndpoint: "$PRIVATE_DNS:6443"
networking:
  podSubnet: "${pod_network_cidr}"
  serviceSubnet: "${service_cidr}"
apiServer:
  certSANs:
  - "$PRIVATE_IP"
  - "$PRIVATE_DNS"
  - "$PUBLIC_IP"
  - "$PUBLIC_DNS"
EOF
  kubeadm config images pull --config /etc/kubernetes-kubeadm-config.yaml
  kubeadm init --config /etc/kubernetes-kubeadm-config.yaml
fi

install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.kube
install -m 0600 -o ubuntu -g ubuntu /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf
retry 30 kubectl get --raw=/readyz

CALICO_OPERATOR="/tmp/tigera-operator-${calico_version}.yaml"
CALICO_RESOURCES="/tmp/custom-resources-${calico_version}.yaml"
curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${calico_version}/manifests/tigera-operator.yaml" -o "$CALICO_OPERATOR"
curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${calico_version}/manifests/custom-resources.yaml" -o "$CALICO_RESOURCES"
sed -ri "s#cidr: 192\\.168\\.0\\.0/16#cidr: ${pod_network_cidr}#" "$CALICO_RESOURCES"
sed -ri 's/encapsulation: (IPIPCrossSubnet|VXLANCrossSubnet)/encapsulation: VXLAN/' "$CALICO_RESOURCES"
kubectl apply -f "$CALICO_OPERATOR"
retry 30 kubectl wait --for=condition=Established crd/installations.operator.tigera.io --timeout=10s
kubectl apply -f "$CALICO_RESOURCES"

echo "Waiting for Kubernetes system workloads to start"
retry 60 kubectl get nodes
kubectl wait --for=condition=Ready node --all --timeout=15m
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=15m

# Never echo this variable: it contains the bootstrap token.
JOIN_COMMAND="$(kubeadm token create --ttl 2h --print-join-command)"
aws ssm put-parameter \
  --region "${aws_region}" \
  --name "${join_parameter_name}" \
  --type SecureString \
  --key-id "${kms_key_id}" \
  --value "$JOIN_COMMAND" \
  --overwrite >/dev/null
unset JOIN_COMMAND

if [[ "${store_kubeconfig}" == "true" ]]; then
  aws ssm put-parameter \
    --region "${aws_region}" \
    --name "${kubeconfig_parameter_name}" \
    --type SecureString \
    --key-id "${kms_key_id}" \
    --value "file:///etc/kubernetes/admin.conf" \
    --overwrite >/dev/null
fi

echo "Waiting for ${expected_node_count} registered Ready nodes"
for attempt in $(seq 1 80); do
  REGISTERED="$(kubectl get nodes --no-headers 2>/dev/null | wc -l)"
  READY="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 ~ /^Ready/ {count++} END {print count+0}')"
  if [[ "$REGISTERED" -eq "${expected_node_count}" && "$READY" -eq "${expected_node_count}" ]]; then
    break
  fi
  if [[ "$attempt" -eq 80 ]]; then
    echo "ERROR: cluster did not reach ${expected_node_count} Ready nodes within 20 minutes" >&2
    exit 1
  fi
  sleep 15
done
kubectl wait --for=condition=Ready pods --all -n calico-system --timeout=10m
kubectl wait --for=condition=Ready pods -l k8s-app=kube-dns -n kube-system --timeout=5m
touch /var/lib/kubeadm-control-plane-complete
echo "Control-plane bootstrap completed successfully"
