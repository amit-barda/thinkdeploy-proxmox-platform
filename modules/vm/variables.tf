variable "node" {
  description = "Proxmox node name"
  type        = string
}

variable "vmid" {
  description = "VM ID number"
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

variable "disk" {
  description = "Disk size (e.g., 50G)"
  type        = string
}

variable "storage" {
  description = "Storage name"
  type        = string
}

variable "network" {
  description = "Network configuration (e.g., bridge=vmbr0)"
  type        = string
}

variable "enabled" {
  description = "Enable VM creation"
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

variable "force_run" {
  description = "Force re-run of VM creation (use timestamp() to force on each apply)"
  type        = string
  default     = ""
}
