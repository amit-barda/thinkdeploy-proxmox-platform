variable "nfs_storages" {
  description = "Map of NFS storage configurations"
  type = map(object({
    server  = string
    export  = string
    content = list(string)
    nodes   = list(string)
    options = map(string)
  }))
  default = {}
}

variable "iscsi_storages" {
  description = "Map of iSCSI storage configurations"
  type = map(object({
    server = string
    target = string
    portal = number
    nodes  = list(string)
  }))
  default = {}
}

variable "ceph_storages" {
  description = "Map of Ceph storage configurations"
  type = map(object({
    pool    = string
    monhost = list(string)
    nodes   = list(string)
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
