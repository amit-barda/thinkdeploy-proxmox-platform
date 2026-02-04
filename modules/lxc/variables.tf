variable "node" {
  description = "Proxmox node name"
  type        = string
}

variable "vmid" {
  description = "LXC container ID number"
  type        = number
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
}

variable "memory" {
  description = "Memory in MB"
  type        = number
}

variable "rootfs" {
  description = "Root filesystem size (e.g., 20G)"
  type        = string
}

variable "ostemplate" {
  description = "OS template (e.g., local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst)"
  type        = string
  default     = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
}

variable "storage" {
  description = "Storage name"
  type        = string
}

variable "enabled" {
  description = "Enable LXC container creation"
  type        = bool
  default     = true
}

# SSH inputs (passed-through)
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

variable "vlan" {
  description = "VLAN ID for network interface (optional)"
  type        = number
  default     = null
}
