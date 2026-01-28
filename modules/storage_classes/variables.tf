variable "enabled" {
  description = "Whether to create StorageClasses."
  type        = bool
  default     = true
}

variable "storage_classes" {
  description = "List of StorageClasses to create."
  type = list(object({
    name                   = string
    provisioner            = optional(string, "ebs.csi.aws.com")
    reclaim_policy         = optional(string, "Delete")
    volume_binding_mode    = optional(string, "WaitForFirstConsumer")
    allow_volume_expansion = optional(bool, true)

    # Convenience for EBS CSI: sets parameters.type when provided (e.g. gp3)
    ebs_type = optional(string)

    # Additional parameters for the provisioner (merged with ebs_type if set)
    parameters = optional(map(string), {})

    # Optional metadata
    annotations = optional(map(string), {})
    labels      = optional(map(string), {})

    # Mark as default StorageClass (annotation)
    is_default = optional(bool, false)
  }))
}
