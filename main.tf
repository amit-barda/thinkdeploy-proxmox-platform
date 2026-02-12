# Cluster module
module "cluster" {
  source = "./modules/cluster"

  create_cluster         = try(var.cluster_config.create_cluster, false)
  cluster_name           = try(var.cluster_config.cluster_name, "")
  primary_node           = try(var.cluster_config.primary_node, "")
  join_node              = try(var.cluster_config.join_node, "")
  ha_enabled             = try(var.cluster_config.ha_enabled, false)
  ha_group_name          = try(var.cluster_config.ha_group_name, "")
  ha_nodes               = try(var.cluster_config.ha_nodes, [])
  corosync_tune          = false
  corosync_token_timeout = 3000
  corosync_join_timeout  = 20

  pm_ssh_host             = var.pm_ssh_host
  pm_ssh_user             = var.pm_ssh_user
  pm_ssh_private_key_path = var.pm_ssh_private_key_path
}

# VM modules
module "vm" {
  for_each = var.vms

  source = "./modules/vm"

  node    = each.value.node
  vmid    = each.value.vmid
  cores   = each.value.cores
  memory  = each.value.memory
  disk    = each.value.disk
  storage = each.value.storage
  network = each.value.network
  enabled = each.value.enabled

  pm_ssh_host             = var.pm_ssh_host
  pm_ssh_user             = var.pm_ssh_user
  pm_ssh_private_key_path = var.pm_ssh_private_key_path
}

# LXC modules
module "lxc" {
  for_each = var.lxcs

  source = "./modules/lxc"

  node      = each.value.node
  vmid      = each.value.vmid
  cores     = each.value.cores
  memory    = each.value.memory
  rootfs    = each.value.rootfs
  storage   = each.value.storage
  ostemplate = try(each.value.ostemplate, "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst")
  enabled   = each.value.enabled

  pm_ssh_host             = var.pm_ssh_host
  pm_ssh_user             = var.pm_ssh_user
  pm_ssh_private_key_path = var.pm_ssh_private_key_path
}

# Storage module
module "storage" {
  source = "./modules/storage"

  nfs_storages   = try(var.storages.nfs, {})
  iscsi_storages = try(var.storages.iscsi, {})
  ceph_storages  = try(var.storages.ceph, {})

  pm_ssh_host             = var.pm_ssh_host
  pm_ssh_user             = var.pm_ssh_user
  pm_ssh_private_key_path = var.pm_ssh_private_key_path
}

# Networking module
module "networking" {
  source = "./modules/networking"

  bridges        = try(var.networking_config.bridges, {})
  vlans          = try(var.networking_config.vlans, {})
  firewall_rules = try(var.networking_config.firewall_rules, {})
  bonds          = try(var.networking_config.bonds, {})

  pm_ssh_host             = var.pm_ssh_host
  pm_ssh_user             = var.pm_ssh_user
  pm_ssh_private_key_path = var.pm_ssh_private_key_path
}

# Security module
module "security" {
  source = "./modules/security"

  rbac_roles              = try(var.security_config.rbac, {})
  api_tokens              = try(var.security_config.api_tokens, {})
  ssh_hardening_enabled   = try(var.security_config.ssh_hardening, false)
  firewall_policy_enabled = try(var.security_config.firewall_policy, false)

  pm_ssh_host             = var.pm_ssh_host
  pm_ssh_user             = var.pm_ssh_user
  pm_ssh_private_key_path = var.pm_ssh_private_key_path
}

# Backup Job modules
module "backup_job" {
  for_each = var.backup_jobs

  source = "./modules/backup_job"

  id       = each.key
  vms      = each.value.vms
  storage  = each.value.storage
  schedule = each.value.schedule
  mode     = each.value.mode
  maxfiles = each.value.maxfiles

  pm_ssh_host             = var.pm_ssh_host
  pm_ssh_user             = var.pm_ssh_user
  pm_ssh_private_key_path = var.pm_ssh_private_key_path
}

# Snapshot modules
module "snapshot" {
  for_each = var.snapshots

  source = "./modules/snapshot"

  node        = each.value.node
  vmid        = each.value.vmid
  snapname    = each.value.snapname
  description = try(each.value.description, "")
  vm_type     = try(each.value.vm_type, "qemu")
  enabled     = each.value.enabled

  pm_ssh_host             = var.pm_ssh_host
  pm_ssh_user             = var.pm_ssh_user
  pm_ssh_private_key_path = var.pm_ssh_private_key_path
}
