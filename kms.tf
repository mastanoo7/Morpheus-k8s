resource "aws_kms_key" "bootstrap" {
  description             = "Encrypts ${local.cluster_name} bootstrap material"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = { Name = "${local.name_prefix}-bootstrap", Role = "BootstrapEncryption" }
}

resource "aws_kms_alias" "bootstrap" {
  name          = "alias/${local.name_prefix}-bootstrap"
  target_key_id = aws_kms_key.bootstrap.key_id
}

# Empty SecureStrings establish ownership so terraform destroy removes the paths.
# User-data overwrites their values; ignore_changes prevents secrets entering plans/state.
resource "aws_ssm_parameter" "join" {
  name        = local.join_path
  description = "Ephemeral kubeadm worker join command"
  type        = "SecureString"
  key_id      = aws_kms_key.bootstrap.arn
  value       = "pending-control-plane-bootstrap"
  tags        = { Name = "${local.name_prefix}-join", Role = "BootstrapSecret" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "kubeconfig" {
  count       = var.store_kubeconfig_in_ssm ? 1 : 0
  name        = local.config_path
  description = "Kubernetes admin kubeconfig"
  type        = "SecureString"
  key_id      = aws_kms_key.bootstrap.arn
  value       = "pending-control-plane-bootstrap"
  tags        = { Name = "${local.name_prefix}-kubeconfig", Role = "BootstrapSecret" }
  lifecycle { ignore_changes = [value] }
}
