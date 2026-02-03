variable "bridges" {
  description = "Map of bridge configurations"
  type = map(object({
    iface = string
    stp   = string
    mtu   = number
  }))
  default = {}
}

variable "vlans" {
  description = "Map of VLAN configurations"
  type = map(object({
    id     = number
    name   = string
    bridge = string
  }))
  default = {}
}

variable "firewall_rules" {
  description = "Map of firewall rule configurations"
  type = map(object({
    action = string
    source = string
    dest   = string
    proto  = string
    dport  = number
  }))
  default = {}
}

variable "bonds" {
  description = "Map of network bond configurations"
  type = map(object({
    interfaces = list(string)
    mode       = string
  }))
  default = {}
}

variable "pm_ssh_host" {
  description = "Proxmox node hostname/IP for SSH"
  type        = string
}

variable "pm_ssh_user" {
  description = "SSH user for Proxmox node"
  type        = string
}

variable "pm_ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
}
