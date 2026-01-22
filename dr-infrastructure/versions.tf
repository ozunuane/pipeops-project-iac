terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # Backend configuration for DR workspace
  # This will be configured by the setup script
  backend "s3" {
    # Configuration will be provided via backend.conf
    # bucket         = "pipeops-terraform-state-dr-<account-id>"
    # key            = "pipeops-project-iac-dr-terraform.tfstate"
    # region         = "us-east-1"
    # encrypt        = true
    # dynamodb_table = "terraform-state-lock-dr"
  }
}
