#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
CLUSTER="${CLUSTER_NAME:-}"
ROLE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="${2:?missing region}"; shift 2 ;;
    --cluster-name) CLUSTER="${2:?missing cluster name}"; shift 2 ;;
    control-plane) ROLE="ControlPlane"; shift ;;
    worker-[1-9]*)
      ROLE="Worker"; NODE_NAME="$1"; shift ;;
    *) echo "Usage: $0 [--region REGION] [--cluster-name NAME] control-plane|worker-N" >&2; exit 2 ;;
  esac
done
[[ -n "$REGION" && -n "$CLUSTER" && -n "$ROLE" ]] ||
  { echo "Region, cluster name, and node are required (or set AWS_REGION and CLUSTER_NAME)" >&2; exit 2; }
command -v aws >/dev/null || { echo "AWS CLI is required" >&2; exit 1; }
command -v session-manager-plugin >/dev/null ||
  { echo "AWS Session Manager plugin is required" >&2; exit 1; }
aws sts get-caller-identity --region "$REGION" >/dev/null ||
  { echo "AWS authentication failed" >&2; exit 1; }

FILTERS=("Name=tag:Cluster,Values=$CLUSTER" "Name=tag:Role,Values=$ROLE" "Name=instance-state-name,Values=running")
if [[ "$ROLE" == "Worker" ]]; then
  FILTERS+=("Name=tag:Name,Values=*$NODE_NAME")
fi
INSTANCE_ID="$(aws ec2 describe-instances --region "$REGION" --filters "${FILTERS[@]}" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)"
[[ "$INSTANCE_ID" != "None" && -n "$INSTANCE_ID" ]] ||
  { echo "No matching running instance found" >&2; exit 1; }
aws ssm describe-instance-information --region "$REGION" \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' --output text | grep -qx Online ||
  { echo "Instance $INSTANCE_ID is not online in Systems Manager" >&2; exit 1; }
exec aws ssm start-session --region "$REGION" --target "$INSTANCE_ID"
