# ====================================================================
# Data Sources - Primary Infrastructure State
# ====================================================================
# Fetch outputs from the primary production Terraform state
# This allows DR infrastructure to reference primary resources (e.g., RDS ARN)

# Remote state data source for primary production infrastructure
data "terraform_remote_state" "primary" {
  backend = "s3"

  config = {
    bucket         = "${var.project_name}-prod-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = var.primary_region
    dynamodb_table = "${var.project_name}-prod-terraform-locks"
    encrypt        = true
  }
}

# ====================================================================
# Locals - Primary Infrastructure Outputs
# ====================================================================
# Extract commonly used values from primary state for easier reference

locals {
  # Primary RDS
  primary_rds_arn         = try(data.terraform_remote_state.primary.outputs.rds_arn, var.primary_rds_arn)
  primary_rds_endpoint    = try(data.terraform_remote_state.primary.outputs.rds_endpoint, "")
  primary_rds_kms_key_arn = try(data.terraform_remote_state.primary.outputs.rds_kms_key_arn, "")
  primary_dr_kms_key_arn  = try(data.terraform_remote_state.primary.outputs.dr_kms_key_arn, var.primary_backup_kms_key_arn)

  # Primary VPC (for reference/peering if needed)
  primary_vpc_id   = try(data.terraform_remote_state.primary.outputs.vpc_id, "")
  primary_vpc_cidr = try(data.terraform_remote_state.primary.outputs.vpc_cidr, "")

  # Primary EKS
  primary_eks_cluster_name     = try(data.terraform_remote_state.primary.outputs.eks_cluster_name, "")
  primary_eks_cluster_endpoint = try(data.terraform_remote_state.primary.outputs.eks_cluster_endpoint, "")

  # Determine if primary RDS exists (for conditional DR replica creation)
  primary_rds_exists = local.primary_rds_arn != "" && local.primary_rds_arn != null
}

# ====================================================================
# AWS Data Sources
# ====================================================================

# Current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Availability zones in DR region
data "aws_availability_zones" "available" {
  state = "available"
}
