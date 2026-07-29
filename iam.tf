resource "aws_iam_role" "control_plane" {
  name = "${local.name_prefix}-control-plane"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole"
    }]
  })
  tags = { Name = "${local.name_prefix}-control-plane-role", Role = "ControlPlane" }
}
resource "aws_iam_role" "worker" {
  name = "${local.name_prefix}-worker"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole"
    }]
  })
  tags = { Name = "${local.name_prefix}-worker-role", Role = "Worker" }
}

resource "aws_iam_role_policy_attachment" "cp_ssm_core" {
  role       = aws_iam_role.control_plane.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "worker_ssm_core" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "control_plane_bootstrap" {
  name = "cluster-bootstrap"
  role = aws_iam_role.control_plane.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = concat([
      {
        Sid = "ManageOnlyClusterBootstrapParameters", Effect = "Allow",
        Action = ["ssm:GetParameter", "ssm:PutParameter"],
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_path}/*"
      },
      {
        Sid = "EncryptBootstrapValues", Effect = "Allow",
        Action = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"],
        Resource = aws_kms_key.bootstrap.arn
      }
    ], var.enable_bootstrap_cloudwatch_logs ? [{
      Sid = "WriteBootstrapLogs", Effect = "Allow",
      Action = ["logs:CreateLogStream", "logs:PutLogEvents"],
      Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/kubeadm/${local.cluster_name}:*"
    }] : [])
  })
}
resource "aws_iam_role_policy" "worker_bootstrap" {
  name = "cluster-bootstrap-read"
  role = aws_iam_role.worker.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = concat([
      {
        Sid = "ReadOnlyJoinParameter", Effect = "Allow",
        Action = ["ssm:GetParameter"],
        Resource = aws_ssm_parameter.join.arn
      },
      {
        Sid = "DecryptJoinValue", Effect = "Allow",
        Action = ["kms:Decrypt"],
        Resource = aws_kms_key.bootstrap.arn
      }
    ], var.enable_bootstrap_cloudwatch_logs ? [{
      Sid = "WriteBootstrapLogs", Effect = "Allow",
      Action = ["logs:CreateLogStream", "logs:PutLogEvents"],
      Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/kubeadm/${local.cluster_name}:*"
    }] : [])
  })
}

resource "aws_iam_instance_profile" "control_plane" {
  name = "${local.name_prefix}-control-plane"
  role = aws_iam_role.control_plane.name
}
resource "aws_iam_instance_profile" "worker" {
  name = "${local.name_prefix}-worker"
  role = aws_iam_role.worker.name
}
