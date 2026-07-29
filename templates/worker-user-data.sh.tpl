#!/usr/bin/env bash
set -euo pipefail

exec > >(tee -a /var/log/kubeadm-bootstrap.log) 2>&1
trap 'rc=$?; echo "ERROR: worker bootstrap failed at line $LINENO (exit $rc)" >&2; exit $rc' ERR
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

retry 18 getent hosts pkgs.k8s.io
retry 18 curl -fsSI --max-time 15 https://pkgs.k8s.io/
retry 12 curl -fsSI --max-time 15 https://registry.k8s.io/v2/
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
retry 5 apt-get install -y "kubelet=${kubernetes_version}-1.1" "kubeadm=${kubernetes_version}-1.1"
apt-mark hold kubelet kubeadm
systemctl enable --now kubelet

if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
fi
retry 10 aws sts get-caller-identity --region "${aws_region}" --output text >/dev/null

if [[ ! -f /etc/kubernetes/kubelet.conf ]]; then
  JOIN_COMMAND=""
  for attempt in $(seq 1 60); do
    JOIN_COMMAND="$(aws ssm get-parameter \
      --region "${aws_region}" \
      --name "${join_parameter_name}" \
      --with-decryption \
      --query Parameter.Value \
      --output text 2>/dev/null || true)"
    if [[ "$JOIN_COMMAND" == kubeadm\ join* ]]; then
      break
    fi
    JOIN_COMMAND=""
    sleep 15
  done
  if [[ -z "$JOIN_COMMAND" ]]; then
    echo "ERROR: encrypted join parameter was not available after 15 minutes" >&2
    exit 1
  fi
  # Execute in-memory. Do not log or persist the secret command.
  read -r -a JOIN_ARGS <<<"$JOIN_COMMAND"
  unset JOIN_COMMAND
  "$${JOIN_ARGS[@]}" --cri-socket unix:///run/containerd/containerd.sock
  unset JOIN_ARGS
fi

systemctl is-active --quiet kubelet
touch /var/lib/kubeadm-worker-complete
echo "Worker bootstrap completed successfully"
