output "snapshot_name" {
  description = "Snapshot name"
  value       = var.snapname
}

output "snapshot_id" {
  description = "Snapshot identifier"
  value       = "${var.vm_type}-${var.vmid}-${var.snapname}"
}
