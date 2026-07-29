resource "aws_security_group" "control_plane" {
  name_prefix = "${local.name_prefix}-control-plane-"
  description = "Kubernetes control-plane; public administration is explicitly restricted"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${local.name_prefix}-control-plane-sg", Role = "ControlPlane" }

  # Nodes require Internet egress for packages, registries, AWS APIs, and SSM.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Required outbound Internet and AWS service access"
  }
}

resource "aws_security_group" "workers" {
  name_prefix = "${local.name_prefix}-workers-"
  description = "Kubernetes workers; no public cluster-internal services"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${local.name_prefix}-workers-sg", Role = "Worker" }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Required outbound Internet and AWS service access"
  }
}

resource "aws_vpc_security_group_ingress_rule" "cp_ssh" {
  count             = var.enable_ssh_access && var.ssh_key_name != null ? 1 : 0
  security_group_id = aws_security_group.control_plane.id
  cidr_ipv4         = var.allowed_admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "Restricted administrator SSH"
}
resource "aws_vpc_security_group_ingress_rule" "worker_ssh" {
  count             = var.enable_ssh_access && var.ssh_key_name != null ? 1 : 0
  security_group_id = aws_security_group.workers.id
  cidr_ipv4         = var.allowed_admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "Restricted administrator SSH"
}
resource "aws_vpc_security_group_ingress_rule" "cp_api_workers" {
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = aws_security_group.workers.id
  from_port                    = 6443
  to_port                      = 6443
  ip_protocol                  = "tcp"
  description                  = "Kubernetes API from workers"
}
resource "aws_vpc_security_group_ingress_rule" "cp_api_self" {
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = aws_security_group.control_plane.id
  from_port                    = 6443
  to_port                      = 6443
  ip_protocol                  = "tcp"
  description                  = "Kubernetes API from control-plane"
}
resource "aws_vpc_security_group_ingress_rule" "cp_api_admin" {
  count             = var.enable_public_api_access ? 1 : 0
  security_group_id = aws_security_group.control_plane.id
  cidr_ipv4         = var.allowed_admin_cidr
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  description       = "Restricted public Kubernetes API"
}

locals {
  cp_self_tcp_ports = {
    etcd      = [2379, 2380]
    kubelet   = [10250, 10250]
    scheduler = [10259, 10259]
    controller = [10257, 10257]
  }
}
resource "aws_vpc_security_group_ingress_rule" "cp_self_tcp" {
  for_each                     = local.cp_self_tcp_ports
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = aws_security_group.control_plane.id
  from_port                    = each.value[0]
  to_port                      = each.value[1]
  ip_protocol                  = "tcp"
  description                  = "${each.key} within control-plane SG"
}
resource "aws_vpc_security_group_ingress_rule" "cp_kubelet_workers" {
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = aws_security_group.workers.id
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
  description                  = "Kubelet from workers where required"
}

locals {
  worker_rules = {
    kubelet_cp     = [10250, 10250, aws_security_group.control_plane.id]
    kubelet_worker = [10250, 10250, aws_security_group.workers.id]
    proxy_cp       = [10256, 10256, aws_security_group.control_plane.id]
    proxy_worker   = [10256, 10256, aws_security_group.workers.id]
  }
}
resource "aws_vpc_security_group_ingress_rule" "worker_tcp" {
  for_each                     = local.worker_rules
  security_group_id            = aws_security_group.workers.id
  referenced_security_group_id = each.value[2]
  from_port                    = each.value[0]
  to_port                      = each.value[1]
  ip_protocol                  = "tcp"
  description                  = each.key
}

resource "aws_vpc_security_group_ingress_rule" "nodeport_tcp" {
  count             = var.enable_nodeport_access ? 1 : 0
  security_group_id = aws_security_group.workers.id
  cidr_ipv4         = var.allowed_admin_cidr
  from_port         = 30000
  to_port           = 32767
  ip_protocol       = "tcp"
  description       = "Restricted TCP NodePort access"
}
resource "aws_vpc_security_group_ingress_rule" "nodeport_udp" {
  count             = var.enable_nodeport_access ? 1 : 0
  security_group_id = aws_security_group.workers.id
  cidr_ipv4         = var.allowed_admin_cidr
  from_port         = 30000
  to_port           = 32767
  ip_protocol       = "udp"
  description       = "Restricted UDP NodePort access"
}

# Calico VXLAN encapsulation is permitted only between node security groups.
locals {
  vxlan_pairs = {
    cp_cp         = [aws_security_group.control_plane.id, aws_security_group.control_plane.id]
    cp_from_worker = [aws_security_group.control_plane.id, aws_security_group.workers.id]
    worker_from_cp = [aws_security_group.workers.id, aws_security_group.control_plane.id]
    worker_worker  = [aws_security_group.workers.id, aws_security_group.workers.id]
  }
}
resource "aws_vpc_security_group_ingress_rule" "calico_vxlan" {
  for_each                     = local.vxlan_pairs
  security_group_id            = each.value[0]
  referenced_security_group_id = each.value[1]
  from_port                    = 4789
  to_port                      = 4789
  ip_protocol                  = "udp"
  description                  = "Calico VXLAN between cluster nodes"
}
