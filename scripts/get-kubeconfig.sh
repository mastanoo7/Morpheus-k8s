#!/usr/bin/env bash
set -euo pipefail

REGION="ap-south-1"
CLUSTER="kubeadm-dev"
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="${2:?missing region}"; shift 2 ;;
    --cluster-name) CLUSTER="${2:?missing cluster name}"; shift 2 ;;
    --output) OUTPUT="${2:?missing output path}"; shift 2 ;;
    *) echo "Usage: $0 --region REGION --cluster-name NAME [--output PATH]" >&2; exit 2 ;;
  esac
done
[[ -n "$REGION" && -n "$CLUSTER" ]] || { echo "Both --region and --cluster-name are required" >&2; exit 2; }
OUTPUT="${OUTPUT:-kubeconfig-$CLUSTER}"

command -v aws >/dev/null || { echo "AWS CLI is required" >&2; exit 1; }
aws sts get-caller-identity --region "$REGION" >/dev/null ||
  { echo "AWS authentication failed for region $REGION" >&2; exit 1; }

INSTANCE_DATA="$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Cluster,Values=$CLUSTER" "Name=tag:Role,Values=ControlPlane" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].[InstanceId,PublicDnsName]' --output text)"
read -r INSTANCE_ID PUBLIC_DNS <<<"$INSTANCE_DATA"
[[ "$INSTANCE_ID" != "None" && -n "$INSTANCE_ID" ]] ||
  { echo "No running control-plane instance found for $CLUSTER" >&2; exit 1; }
[[ "$PUBLIC_DNS" != "None" && -n "$PUBLIC_DNS" ]] ||
  { echo "Control-plane has no public DNS name" >&2; exit 1; }

umask 077
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
if ! aws ssm get-parameter --region "$REGION" \
  --name "/kubeadm/$CLUSTER/admin-kubeconfig" --with-decryption \
  --query Parameter.Value --output text >"$TMP"; then
  echo "Unable to retrieve kubeconfig; verify SSM/KMS permissions and control-plane bootstrap" >&2
  exit 1
fi
grep -q '^apiVersion:' "$TMP" || { echo "Stored kubeconfig is not ready or valid" >&2; exit 1; }
sed -i.bak -E "s#^([[:space:]]*server: https://)[^:]+(:6443)#\1$PUBLIC_DNS\2#" "$TMP"
rm -f "$TMP.bak"
install -m 0600 "$TMP" "$OUTPUT"
echo "Kubeconfig written securely to $OUTPUT (control-plane: $INSTANCE_ID)"
