resource "aws_instance" "worker" {
  count = var.worker_count

  ami                         = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type               = var.worker_instance_type
  subnet_id                   = aws_subnet.public[tostring(count.index % length(aws_subnet.public))].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.workers.id]
  iam_instance_profile        = aws_iam_instance_profile.worker.name
  key_name                    = var.enable_ssh_access && var.ssh_key_name != null ? var.ssh_key_name : null
  monitoring                  = var.enable_detailed_monitoring

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
  root_block_device {
    encrypted   = true
    kms_key_id  = aws_kms_key.bootstrap.arn
    volume_size = var.worker_root_volume_size
    volume_type = var.root_volume_type
  }
  user_data = templatefile("${path.module}/templates/worker-user-data.sh.tpl", {
    aws_region               = var.aws_region
    join_parameter_name      = aws_ssm_parameter.join.name
    kubernetes_version       = var.kubernetes_version
    kubernetes_minor_version = var.kubernetes_minor_version
  })
  user_data_replace_on_change = false

  tags = { Name = "${local.name_prefix}-worker-${count.index + 1}", Role = "Worker" }

  depends_on = [
    aws_instance.control_plane,
    aws_route_table_association.public,
    aws_iam_role_policy.worker_bootstrap,
    aws_iam_role_policy_attachment.worker_ssm_core
  ]
}
