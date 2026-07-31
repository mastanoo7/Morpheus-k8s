variable "aws_region" {
  type        = string
  description = "AWS region."
  default     = "ap-south-1"
}
variable "aws_profile" {
  type        = string
  description = "Optional shared AWS CLI profile; null uses the normal credential chain."
  default     = null
  nullable    = true
}
variable "project_name" {
  type        = string
  default     = "kubeadm-aws"
  description = "Project/resource name prefix."
}
variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment tag."
}
variable "cluster_name" {
  type        = string
  default     = "kubeadm-dev"
  description = "Cluster name and cluster-specific IAM/SSM namespace."
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,48}[a-zA-Z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 3-50 alphanumeric/hyphen characters."
  }
}
variable "vpc_cidr" {
  type        = string
  default     = "10.10.0.0/16"
  description = "VPC IPv4 CIDR."
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}
variable "availability_zones" {
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
  description = "Exactly two AZs."
  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Provide exactly two distinct availability zones."
  }
}
variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.10.1.0/24", "10.10.2.0/24"]
  description = "Exactly two public subnet CIDRs."
  validation {
    condition     = length(var.public_subnet_cidrs) == 2 && alltrue([for c in var.public_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "Provide exactly two valid IPv4 CIDRs."
  }
}
variable "control_plane_instance_type" {
  type        = string
  default     = "c7i-flex.large"
  description = "Control-plane EC2 type."
}
variable "worker_instance_type" {
  type        = string
  default     = "c7i-flex.large"
  description = "Worker EC2 type."
}
variable "worker_count" {
  type        = number
  default     = 2
  description = "Number of workers."
  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 20 && floor(var.worker_count) == var.worker_count
    error_message = "worker_count must be an integer from 1 through 20."
  }
}
variable "control_plane_root_volume_size" {
  type        = number
  default     = 30
  description = "Control-plane root disk GiB."
}
variable "worker_root_volume_size" {
  type        = number
  default     = 30
  description = "Worker root disk GiB."
}
variable "root_volume_type" {
  type        = string
  default     = "gp3"
  description = "EBS root volume type."
  validation {
    condition     = contains(["gp3", "gp2", "io1", "io2"], var.root_volume_type)
    error_message = "Use gp3, gp2, io1, or io2."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.35.6"
  description = "Pinned Kubernetes 1.35 patch version (resolved from the official release source on 2026-07-26)."
  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Use a version such as 1.35.6 without a v prefix."
  }
}
variable "kubernetes_minor_version" {
  type        = string
  default     = "v1.35"
  description = "pkgs.k8s.io repository stream."
  validation {
    condition     = can(regex("^v1\\.[0-9]+$", var.kubernetes_minor_version))
    error_message = "Use a minor stream such as v1.35."
  }
}
variable "calico_version" {
  type        = string
  default     = "v3.32.0"
  description = "Pinned Calico release."
}
variable "pod_network_cidr" {
  type        = string
  default     = "192.168.0.0/16"
  description = "Kubernetes pod CIDR."
}
variable "service_cidr" {
  type        = string
  default     = "10.96.0.0/12"
  description = "Kubernetes service CIDR."
}
variable "ssh_key_name" {
  type        = string
  default     = "morpheus"
  nullable    = true
  description = "Existing EC2 key pair attached to the instances. Set to null to attach no key pair."
}
variable "enable_ssh_access" {
  type        = bool
  default     = false
  description = "Enable TCP/22 from allowed_admin_cidr; also requires ssh_key_name."
}
variable "allowed_admin_cidr" {
  type        = string
  default     = "203.0.113.10/32"
  description = "Trusted administrator IPv4 CIDR; must not be world-open."
  validation {
    condition     = can(cidrnetmask(var.allowed_admin_cidr)) && var.allowed_admin_cidr != "0.0.0.0/0"
    error_message = "allowed_admin_cidr must be a valid restricted IPv4 CIDR."
  }
}
variable "enable_public_api_access" {
  type        = bool
  default     = true
  description = "Allow API TCP/6443 from allowed_admin_cidr."
}
variable "enable_nodeport_access" {
  type        = bool
  default     = false
  description = "Allow TCP/UDP NodePort range from allowed_admin_cidr."
}
variable "enable_detailed_monitoring" {
  type        = bool
  default     = false
  description = "Enable EC2 one-minute monitoring."
}
variable "store_kubeconfig_in_ssm" {
  type        = bool
  default     = true
  description = "Store admin kubeconfig as an encrypted SecureString for retrieval."
}
variable "enable_bootstrap_cloudwatch_logs" {
  type        = bool
  default     = false
  description = "Grant least-privilege CloudWatch Logs writes. Agent configuration is left to operators."
}
