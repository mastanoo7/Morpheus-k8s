output "vpc_id" { value = aws_vpc.this.id }
output "internet_gateway_id" { value = aws_internet_gateway.this.id }
output "public_subnet_ids" { value = [for s in aws_subnet.public : s.id] }
output "public_route_table_id" { value = aws_route_table.public.id }
output "control_plane_instance_id" { value = aws_instance.control_plane.id }
output "control_plane_private_ip" { value = aws_instance.control_plane.private_ip }
output "control_plane_public_ip" { value = aws_instance.control_plane.public_ip }
output "control_plane_private_dns" { value = aws_instance.control_plane.private_dns }
output "control_plane_public_dns" { value = aws_instance.control_plane.public_dns }
output "worker_instance_ids" { value = aws_instance.worker[*].id }
output "worker_private_ips" { value = aws_instance.worker[*].private_ip }
output "worker_public_ips" { value = aws_instance.worker[*].public_ip }
output "worker_private_dns_names" { value = aws_instance.worker[*].private_dns }
output "worker_public_dns_names" { value = aws_instance.worker[*].public_dns }
output "ssm_parameter_store_path" { value = local.ssm_path }
output "cluster_name" { value = local.cluster_name }
output "aws_region" { value = var.aws_region }
output "ssm_connection_commands" {
  value = concat(
    ["./scripts/connect-ssm.sh --region ${var.aws_region} --cluster-name ${local.cluster_name} control-plane"],
    [for i in range(var.worker_count) : "./scripts/connect-ssm.sh --region ${var.aws_region} --cluster-name ${local.cluster_name} worker-${i + 1}"]
  )
}
output "kubeconfig_retrieval_command" {
  value = "./scripts/get-kubeconfig.sh --region ${var.aws_region} --cluster-name ${local.cluster_name}"
}
output "cluster_verification_command" {
  value = "KUBECONFIG=$PWD/kubeconfig-${local.cluster_name} ./scripts/verify-cluster.sh"
}
