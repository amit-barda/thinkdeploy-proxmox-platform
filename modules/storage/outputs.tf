output "nfs_storages" {
  description = "NFS storage names"
  value       = keys(var.nfs_storages)
}
