variable "bridges" {
  description = "Map of bridge configurations"
  type = map(object({
    iface        = string
    stp          = string
    mtu          = number
    ipv4_cidr    = optional(string, "")
    ipv4_gateway = optional(string, "")
    ipv6_cidr    = optional(string, "")
    ipv6_gateway = optional(string, "")
    autostart    = optional(string, "N")
    vlan_aware   = optional(string, "N")
    comment      = optional(string, "")
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
    type   = optional(string, "in")
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

variable "sdns" {
  description = "Map of SDN zone configurations"
  type = map(object({
    name   = string
    type   = string
    bridge = string
    vlan   = number
  }))
  default = {}
}

variable "nats" {
  description = "Map of NAT rule configurations"
  type = map(object({
    name      = string
    source    = string
    interface = string
    snat      = string
  }))
  default = {}
}

variable "mtus" {
  description = "Map of MTU configurations for interfaces"
  type = map(object({
    interface = string
    mtu       = number
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
