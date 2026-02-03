output "vm_ids" {
  description = "List of created VM IDs"
  value       = [for vm in module.vm : vm.vmid]
}

output "backup_job_ids" {
  description = "List of created backup job IDs"
  value       = [for job in module.backup_job : job.id]
}
