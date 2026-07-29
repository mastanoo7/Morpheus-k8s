#!/usr/bin/env bash
set -euo pipefail

command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 1; }
CONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[[ -f "$CONFIG" ]] || { echo "Kubeconfig not found: $CONFIG" >&2; exit 1; }

kubectl --request-timeout=15s cluster-info
kubectl get nodes -o wide
kubectl get pods -A
kubectl get pods -n kube-system

NODE_COUNT="$(kubectl get nodes --no-headers | wc -l | tr -d ' ')"
[[ "$NODE_COUNT" -eq 3 ]] || { echo "Expected exactly 3 nodes; found $NODE_COUNT" >&2; exit 1; }
NOT_READY="$(kubectl get nodes --no-headers | awk '$2 !~ /^Ready/ {count++} END {print count+0}')"
[[ "$NOT_READY" -eq 0 ]] || { echo "$NOT_READY node(s) are not Ready" >&2; exit 1; }

BAD_SYSTEM="$(kubectl get pods -n kube-system --no-headers | awk '$3 != "Running" && $3 != "Completed" {count++} END {print count+0}')"
[[ "$BAD_SYSTEM" -eq 0 ]] || { echo "$BAD_SYSTEM kube-system pod(s) are unhealthy" >&2; exit 1; }
kubectl get pods -A --no-headers | grep -Ei 'calico|tigera' | grep -q 'Running' ||
  { echo "No running Calico/Tigera pods found" >&2; exit 1; }
kubectl get pods -n kube-system --no-headers | grep -i coredns | grep -q 'Running' ||
  { echo "CoreDNS is not running" >&2; exit 1; }
echo "Cluster verification passed"
