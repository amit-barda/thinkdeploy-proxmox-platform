# Proxmox connection variables
variable "pm_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://localhost:8006/api2/json"
}

variable "pm_user" {
  description = "Proxmox username"
  type        = string
  default     = "root@pam"
}

variable "pm_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "pm_tls_insecure" {
  description = "Skip TLS verification"
  type        = bool
  default     = false
}

# SSH to Proxmox node for pvesh execution
variable "pm_ssh_host" {
  description = "Proxmox node hostname/IP for SSH (to run pvesh)"
  type        = string
  default     = "localhost"
}

variable "pm_ssh_user" {
  description = "SSH user to connect to Proxmox node"
  type        = string
  default     = "root"
}

variable "pm_ssh_private_key_path" {
  description = "Path to SSH private key for Proxmox node"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "vm_force_run" {
  description = "Force re-run of VM creation (use timestamp() to force on each apply, or empty string to disable)"
  type        = string
  default     = ""
}

# VM configuration - Interactive input
variable "vms" {
  description = "Map of VM configurations"
  type = map(object({
    node    = string
    vmid    = number
    cores   = number
    memory  = number
    disk    = string
    storage = string
    network = string
    enabled = optional(bool, true)
  }))
  default = {}
}

# LXC configuration
variable "lxcs" {
  description = "Map of LXC container configurations"
  type = map(object({
    node       = string
    vmid       = number
    cores      = number
    memory     = number
    rootfs     = string
    storage    = string
    ostemplate = optional(string, "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst")
    enabled    = optional(bool, true)
  }))
  default = {}
}

# Cluster configuration
variable "cluster_config" {
  description = "Cluster configuration"
  type = object({
    create_cluster = optional(bool, false)
    cluster_name   = optional(string, "")
    primary_node   = optional(string, "")
    join_node      = optional(string, "")
    ha_enabled     = optional(bool, false)
    ha_group_name  = optional(string, "")
    ha_nodes       = optional(list(string), [])
  })
  default = {}
}

# Storage configuration
variable "storages" {
  description = "Map of storage configurations"
  type        = map(any)
  default     = {}
}

# Networking configuration
variable "networking_config" {
  description = "Networking configuration"
  type        = map(any)
  default     = {}
}

# Security configuration
variable "security_config" {
  description = "Security configuration"
  type        = map(any)
  default     = {}
}

# Backup Job configuration - Interactive input
variable "backup_jobs" {
  description = "Map of backup job configurations"
  type = map(object({
    vms      = list(string)
    storage  = string
    schedule = string
    mode     = string
    maxfiles = number
  }))
  default = {}

  validation {
    condition = alltrue([
      for job in var.backup_jobs : contains(["snapshot", "stop", "suspend"], job.mode)
    ])
    error_message = "Backup job mode must be one of: snapshot, stop, suspend."
  }
}

# Snapshot configuration
variable "snapshots" {
  description = "Map of snapshot configurations"
  type = map(object({
    node        = string
    vmid        = number
    snapname    = string
    description = optional(string, "")
    vm_type     = optional(string, "qemu")
    enabled     = optional(bool, true)
  }))
  default = {}
}

# Autoscaling configuration
variable "autoscaling_config" {
  description = "Autoscaling configuration for VM groups"
  type = object({
    group      = optional(string, "")
    min        = optional(number, 2)
    max        = optional(number, 10)
    scale_up   = optional(number, 80)
    scale_down = optional(number, 30)
  })
  default = {}
}
