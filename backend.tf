terraform {
  backend "s3" {
    # Backend configuration will be provided via terraform init
    # Example:
    # bucket         = "your-terraform-state-bucket"
    # key            = "eks-production/terraform.tfstate"
    # region         = "us-west-2"
    # encrypt        = true
    # dynamodb_table = "terraform-state-lock"
  }
}