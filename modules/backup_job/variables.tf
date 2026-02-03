variable "id" {
  description = "Unique identifier for the backup job"
  type        = string
}

variable "vms" {
  description = "List of VM IDs to backup"
  type        = list(string)
}

variable "storage" {
  description = "Storage name to backup to"
  type        = string
}

variable "schedule" {
  description = "Cron schedule for the backup job"
  type        = string
}

variable "mode" {
  description = "Backup mode: snapshot, stop, or suspend"
  type        = string

  validation {
    condition     = contains(["snapshot", "stop", "suspend"], var.mode)
    error_message = "Mode must be one of: snapshot, stop, suspend."
  }
}

variable "maxfiles" {
  description = "Maximum number of backup files to keep"
  type        = number
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
