locals {
  cluster_name = var.cluster_name
  name_prefix  = "${var.project_name}-${var.environment}"
  ssm_path     = "/kubeadm/${local.cluster_name}"
  join_path    = "${local.ssm_path}/join-command"
  config_path  = "${local.ssm_path}/admin-kubeconfig"

  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Cluster     = local.cluster_name
  }
}
