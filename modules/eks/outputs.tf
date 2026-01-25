output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.cluster_id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "cluster_version" {
  description = "The Kubernetes server version for the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS node group"
  value       = aws_security_group.node.id
}

# Note: node_group_arn and node_group_status outputs removed
# EKS Auto Mode manages node groups automatically - they are not Terraform-managed resources
# Use AWS Console or CLI to view Auto Mode node pool status:
#   aws eks describe-nodegroup --cluster-name <cluster> --nodegroup-name <nodegroup>

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Identity Provider if enabled"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "cluster_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "IAM role ARN of the EKS node group"
  value       = aws_iam_role.node.arn
}

output "node_instance_profile_arn" {
  description = "IAM instance profile ARN for EKS nodes (used by Auto Mode)"
  value       = aws_iam_instance_profile.node.arn
}

output "node_instance_profile_name" {
  description = "IAM instance profile name for EKS nodes (used by Auto Mode)"
  value       = aws_iam_instance_profile.node.name
}