variable "create_cluster" {
  description = "Create new cluster"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
  default     = ""
}

variable "primary_node" {
  description = "Primary node for cluster creation"
  type        = string
  default     = ""
}

variable "join_node" {
  description = "Node to join to cluster"
  type        = string
  default     = ""
}

variable "cluster_ip" {
  description = "Cluster IP for joining"
  type        = string
  default     = ""
}

variable "ha_enabled" {
  description = "Enable HA"
  type        = bool
  default     = false
}

variable "ha_group_name" {
  description = "HA group name"
  type        = string
  default     = ""
}

variable "ha_nodes" {
  description = "HA nodes list"
  type        = list(string)
  default     = []
}

variable "corosync_tune" {
  description = "Tune Corosync"
  type        = bool
  default     = false
}

variable "corosync_token_timeout" {
  description = "Corosync token timeout (ms)"
  type        = number
  default     = 3000
}

variable "corosync_join_timeout" {
  description = "Corosync join timeout (ms)"
  type        = number
  default     = 20
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
