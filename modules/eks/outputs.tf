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

output "node_group_arn" {
  description = "ARN of the EKS managed node group"
  value       = aws_eks_node_group.main.arn
}

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
  description = "IAM instance profile ARN for EKS nodes (Karpenter uses this)"
  value       = aws_iam_instance_profile.node.arn
}

output "node_instance_profile_name" {
  description = "IAM instance profile name for EKS nodes (Karpenter defaultInstanceProfile)"
  value       = aws_iam_instance_profile.node.name
}

output "karpenter_role_arn" {
  description = "IAM role ARN for Karpenter controller (IRSA)"
  value       = aws_iam_role.karpenter.arn
}

output "karpenter_role_name" {
  description = "IAM role name for Karpenter controller (for policy attachment)"
  value       = aws_iam_role.karpenter.name
}

output "aws_load_balancer_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller (IRSA). Set when enable_aws_load_balancer_controller_addon is true."
  value       = var.enable_aws_load_balancer_controller_addon ? aws_iam_role.aws_load_balancer_controller[0].arn : null
}