# EKS Access Entries – IAM principals with level-based permissions (admin, devops, dev, qa)
# https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html

locals {
  access_level_policy = {
    admin  = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    devops = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
    dev    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
    qa     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  }
  cluster_scoped_entries   = { for k, v in var.cluster_access_entries : k => v if length(coalesce(v.namespaces, [])) == 0 }
  namespace_scoped_entries = { for k, v in var.cluster_access_entries : k => v if length(coalesce(v.namespaces, [])) > 0 }
}

resource "aws_eks_access_entry" "cluster_access" {
  for_each      = var.cluster_access_entries
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_scoped" {
  for_each      = local.cluster_scoped_entries
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value.principal_arn
  policy_arn    = local.access_level_policy[each.value.level]

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_access]
}

resource "aws_eks_access_policy_association" "namespace_scoped" {
  for_each      = local.namespace_scoped_entries
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value.principal_arn
  policy_arn    = local.access_level_policy[each.value.level]

  access_scope {
    type       = "namespace"
    namespaces = each.value.namespaces
  }

  depends_on = [aws_eks_access_entry.cluster_access]
}
