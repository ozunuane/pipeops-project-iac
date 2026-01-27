# EKS Access Entries – grant IAM principals cluster access (fix "Unauthorized" / "must be logged in")
# https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html

resource "aws_eks_access_entry" "cluster_access" {
  for_each      = toset(var.cluster_access_iam_principal_arns)
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_admin" {
  for_each      = toset(var.cluster_access_iam_principal_arns)
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_access]
}
