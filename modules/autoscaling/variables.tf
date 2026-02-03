variable "group" {
  description = "Autoscaling group name"
  type        = string
}

variable "min" {
  description = "Minimum number of VMs/LXCs"
  type        = number
  default     = 2
}

variable "max" {
  description = "Maximum number of VMs/LXCs"
  type        = number
  default     = 10
}

variable "scale_up" {
  description = "Scale-up threshold percentage"
  type        = number
  default     = 80
}

variable "scale_down" {
  description = "Scale-down threshold percentage"
  type        = number
  default     = 30
}

variable "vm_autoscale_repo" {
  description = "GitHub repository URL for proxmox-vm-autoscale"
  type        = string
  default     = "https://github.com/fabriziosalmi/proxmox-vm-autoscale.git"
}

variable "lxc_autoscale_repo" {
  description = "GitHub repository URL for proxmox-lxc-autoscale"
  type        = string
  default     = "https://github.com/fabriziosalmi/proxmox-lxc-autoscale.git"
}

variable "cluster_balancer_repo" {
  description = "GitHub repository URL for proxmox-cluster-balancer"
  type        = string
  default     = "https://github.com/fabriziosalmi/proxmox-cluster-balancer.git"
}

variable "install_path" {
  description = "Installation path for autoscaling tools"
  type        = string
  default     = "/opt/proxmox-autoscaling"
}

variable "enabled" {
  description = "Enable autoscaling"
  type        = bool
  default     = true
}

variable "pm_ssh_host" {
  description = "Proxmox node hostname/IP for SSH"
  type        = string
}

variable "pm_ssh_user" {
  description = "SSH user to connect to Proxmox node"
  type        = string
}

variable "pm_ssh_private_key_path" {
  description = "Path to SSH private key for Proxmox node"
  type        = string
}

variable "resource_type" {
  description = "Type of resource to autoscale: 'vm' or 'lxc'"
  type        = string
  default     = "vm"
  
  validation {
    condition     = contains(["vm", "lxc"], var.resource_type)
    error_message = "Resource type must be either 'vm' or 'lxc'."
  }
}
