# EKS Access Entries – IAM principals with level-based permissions (admin, devops, dev, qa)
# https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html
# When eks_exec_role_arn is set (or eks-exec-role-arn.txt exists), CI assumes that role for EKS; it is merged here.
# Only created when create_eks = true.

locals {
  access_level_policy = {
    admin  = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    devops = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
    dev    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
    qa     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  }
  _eks_cluster_name        = var.create_eks ? module.eks[0].cluster_name : "local"
  _eks_exec_arn            = length(var.eks_exec_role_arn) > 0 ? var.eks_exec_role_arn : (fileexists("${path.module}/environments/${var.environment}/eks-exec-role-arn.txt") ? trimspace(file("${path.module}/environments/${var.environment}/eks-exec-role-arn.txt")) : "")
  _eks_exec_entry          = length(local._eks_exec_arn) > 0 ? { "eks-exec" = { principal_arn = local._eks_exec_arn, level = "admin", namespaces = null } } : {}
  _entries_merged          = merge(var.cluster_access_entries, local._eks_exec_entry)
  _entries_for_eks         = var.create_eks ? local._entries_merged : {}
  _get_token_args          = length(local._eks_exec_arn) > 0 ? concat(["eks", "get-token", "--cluster-name", local._eks_cluster_name], ["--role-arn", local._eks_exec_arn]) : ["eks", "get-token", "--cluster-name", local._eks_cluster_name]
  cluster_scoped_entries   = { for k, v in local._entries_for_eks : k => v if length(coalesce(v.namespaces, [])) == 0 }
  namespace_scoped_entries = { for k, v in local._entries_for_eks : k => v if length(coalesce(v.namespaces, [])) > 0 }
}

resource "aws_eks_access_entry" "cluster_access" {
  for_each      = local._entries_for_eks
  cluster_name  = local._eks_cluster_name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_scoped" {
  for_each      = local.cluster_scoped_entries
  cluster_name  = local._eks_cluster_name
  principal_arn = each.value.principal_arn
  policy_arn    = local.access_level_policy[each.value.level]

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_access]
}

resource "aws_eks_access_policy_association" "namespace_scoped" {
  for_each      = local.namespace_scoped_entries
  cluster_name  = local._eks_cluster_name
  principal_arn = each.value.principal_arn
  policy_arn    = local.access_level_policy[each.value.level]

  access_scope {
    type       = "namespace"
    namespaces = each.value.namespaces
  }

  depends_on = [aws_eks_access_entry.cluster_access]
}
