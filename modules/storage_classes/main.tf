locals {
  storage_classes_by_name = { for sc in var.storage_classes : sc.name => sc }
}

resource "kubernetes_storage_class_v1" "this" {
  for_each = var.enabled ? local.storage_classes_by_name : {}

  metadata {
    name = each.value.name

    annotations = merge(
      each.value.annotations,
      each.value.is_default ? {
        "storageclass.kubernetes.io/is-default-class"      = "true"
        "storageclass.beta.kubernetes.io/is-default-class" = "true"
      } : {}
    )

    labels = each.value.labels
  }

  storage_provisioner    = each.value.provisioner
  reclaim_policy         = each.value.reclaim_policy
  volume_binding_mode    = each.value.volume_binding_mode
  allow_volume_expansion = each.value.allow_volume_expansion

  parameters = merge(
    each.value.parameters,
    each.value.ebs_type != null ? { type = each.value.ebs_type } : {}
  )
}

