variable "node" {
  description = "Proxmox node name"
  type        = string
}

variable "vmid" {
  description = "VM/CT ID number"
  type        = number
}

variable "snapname" {
  description = "Snapshot name"
  type        = string
}

variable "description" {
  description = "Snapshot description"
  type        = string
  default     = ""
}

variable "vm_type" {
  description = "VM type: qemu or lxc"
  type        = string
  default     = "qemu"
}

variable "enabled" {
  description = "Enable snapshot creation"
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
