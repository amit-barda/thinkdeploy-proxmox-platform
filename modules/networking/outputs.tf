output "bridges" {
  description = "Bridge names"
  value       = keys(var.bridges)
}

output "vlans" {
  description = "VLAN configurations"
  value = {
    for k, v in var.vlans : k => {
      id     = v.id
      name   = v.name
      bridge = v.bridge
    }
  }
}
