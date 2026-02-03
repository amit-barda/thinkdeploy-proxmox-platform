variable "rbac_roles" {
  description = "Map of RBAC role configurations"
  type = map(object({
    userid     = string
    role       = string
    privileges = list(string)
  }))
  default = {}
}

variable "api_tokens" {
  description = "Map of API token configurations"
  type = map(object({
    userid  = string
    tokenid = string
    expire  = number
  }))
  default = {}
}

variable "ssh_hardening_enabled" {
  description = "Enable SSH hardening"
  type        = bool
  default     = false
}

variable "ssh_permit_root" {
  description = "Permit root login (yes/no)"
  type        = string
  default     = "no"
}

variable "ssh_password_auth" {
  description = "Password authentication (yes/no)"
  type        = string
  default     = "no"
}

variable "ssh_max_tries" {
  description = "Max authentication tries"
  type        = number
  default     = 3
}

variable "firewall_policy_enabled" {
  description = "Enable firewall policy"
  type        = bool
  default     = false
}

variable "firewall_default_policy" {
  description = "Firewall default policy"
  type        = string
  default     = "DROP"
}

variable "firewall_log_level" {
  description = "Firewall log level"
  type        = string
  default     = "info"
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
