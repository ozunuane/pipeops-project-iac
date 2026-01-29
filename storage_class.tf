locals {
  default_gp3_storageclass_name = "${var.project_name}-${var.environment}-gp3-storageclass"

  effective_storage_classes = (
    var.storage_classes != null
    ? var.storage_classes
    : tolist([
      {
        name     = local.default_gp3_storageclass_name
        ebs_type = "gp3"
      }
    ])
  )
}

# ==========================================
# Kubernetes StorageClasses
# ==========================================
# EKS Auto Mode provides the CSI driver but does not create StorageClasses.
# This module ensures required StorageClasses exist (e.g. for monitoring PVCs).
module "storage_classes" {
  source = "./modules/storage_classes"

  enabled         = var.create_eks && var.cluster_exists
  storage_classes = local.effective_storage_classes

  depends_on = [module.eks]
}
