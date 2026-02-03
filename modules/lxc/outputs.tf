output "lxc_id" {
  description = "LXC container ID"
  value       = var.vmid
}

output "lxc_name" {
  description = "LXC container name"
  value       = "lxc-${var.vmid}"
}
