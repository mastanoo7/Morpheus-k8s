resource "aws_instance" "control_plane" {
  ami                         = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type               = var.control_plane_instance_type
  subnet_id                   = aws_subnet.public["0"].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.control_plane.id]
  iam_instance_profile        = aws_iam_instance_profile.control_plane.name
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
    volume_size = var.control_plane_root_volume_size
    volume_type = var.root_volume_type
  }
  user_data = templatefile("${path.module}/templates/control-plane-user-data.sh.tpl", {
    aws_region               = var.aws_region
    cluster_name             = local.cluster_name
    join_parameter_name      = aws_ssm_parameter.join.name
    kubeconfig_parameter_name = local.config_path
    store_kubeconfig         = var.store_kubeconfig_in_ssm
    kms_key_id               = aws_kms_key.bootstrap.arn
    kubernetes_version       = var.kubernetes_version
    kubernetes_minor_version = var.kubernetes_minor_version
    calico_version           = var.calico_version
    pod_network_cidr         = var.pod_network_cidr
    service_cidr             = var.service_cidr
    expected_node_count      = var.worker_count + 1
  })
  user_data_replace_on_change = false

  tags = { Name = "${local.name_prefix}-control-plane", Role = "ControlPlane" }

  depends_on = [
    aws_route.internet,
    aws_route_table_association.public,
    aws_iam_role_policy.control_plane_bootstrap,
    aws_iam_role_policy_attachment.cp_ssm_core
  ]
}
