# Storage management using pvesh CLI
resource "null_resource" "nfs_storage" {
  for_each = var.nfs_storages

  triggers = {
    storage_name = each.key
    server       = each.value.server
    export       = each.value.export
    content      = join(",", each.value.content)
    nodes        = join(",", each.value.nodes)
    options      = jsonencode(each.value.options)
    pm_ssh_host  = var.pm_ssh_host
    pm_ssh_user  = var.pm_ssh_user
    pm_ssh_key   = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Create NFS storage
      for node in $(echo "${self.triggers.nodes}" | tr ',' ' '); do
        ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
          "pvesh create /storage --storage '${self.triggers.storage_name}' --type nfs --server '${self.triggers.server}' --export '${self.triggers.export}' --content '${self.triggers.content}' --nodes \$node" 2>&1 || echo "Storage may already exist"
      done
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Delete NFS storage
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh delete /storage/${self.triggers.storage_name}" || true
    EOT
  }
}

resource "null_resource" "iscsi_storage" {
  for_each = var.iscsi_storages

  triggers = {
    storage_name = each.key
    server       = each.value.server
    target       = each.value.target
    portal       = each.value.portal
    nodes        = join(",", each.value.nodes)
    pm_ssh_host  = var.pm_ssh_host
    pm_ssh_user  = var.pm_ssh_user
    pm_ssh_key   = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Create iSCSI storage
      for node in $(echo "${self.triggers.nodes}" | tr ',' ' '); do
        ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
          "pvesh create /storage --storage ${self.triggers.storage_name} --type iscsi --portal ${self.triggers.server}:${self.triggers.portal} --target ${self.triggers.target} --nodes \$node" || echo "Storage may already exist"
      done
    EOT
  }
}

resource "null_resource" "ceph_storage" {
  for_each = var.ceph_storages

  triggers = {
    storage_name = each.key
    pool         = each.value.pool
    monhost      = join(",", each.value.monhost)
    nodes        = join(",", each.value.nodes)
    pm_ssh_host  = var.pm_ssh_host
    pm_ssh_user  = var.pm_ssh_user
    pm_ssh_key   = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Create Ceph storage
      for node in $(echo "${self.triggers.nodes}" | tr ',' ' '); do
        ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
          "pvesh create /storage --storage ${self.triggers.storage_name} --type rbd --pool ${self.triggers.pool} --monhost ${self.triggers.monhost} --nodes \$node" || echo "Storage may already exist"
      done
    EOT
  }
}
