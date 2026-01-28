output "names" {
  description = "Names of StorageClasses created."
  value       = keys(kubernetes_storage_class_v1.this)
}

output "storage_classes" {
  description = "Full StorageClass resources."
  value       = kubernetes_storage_class_v1.this
}

