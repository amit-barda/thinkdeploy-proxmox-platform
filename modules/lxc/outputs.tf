output "lxc_id" {
  description = "LXC container ID"
  value       = var.vmid
}

output "lxc_name" {
  description = "LXC container name"
  value       = "lxc-${var.vmid}"
}

output "vlan" {
  description = "VLAN ID configured for LXC container"
  value       = var.vlan
}
