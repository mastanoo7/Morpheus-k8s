provider "aws" {
  region     = var.aws_region
  profile    = var.aws_profile
  access_key = var.access_key
  secret_key = var.secret_key
  token      = var.session_token

  default_tags {
    tags = local.common_tags
  }
}
