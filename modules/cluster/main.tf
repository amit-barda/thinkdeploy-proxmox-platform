# Cluster management using pvesh CLI
resource "null_resource" "cluster_create" {
  count = var.create_cluster ? 1 : 0

  triggers = {
    cluster_name = var.cluster_name
    primary_node = var.primary_node
    pm_ssh_host  = var.pm_ssh_host
    pm_ssh_user  = var.pm_ssh_user
    pm_ssh_key   = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Create cluster
      # CRITICAL: Check if cluster already exists in Proxmox (source of truth)
      # This prevents attempting to create a cluster that already exists (brownfield scenario)
      CLUSTER_STATUS=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvecm status 2>&1" | grep -q "Cluster information\|Cluster name" && echo "exists" || echo "none")
      
      if [ "$CLUSTER_STATUS" = "exists" ]; then
        EXISTING_NAME=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
          "pvecm status 2>&1" | grep -i "Cluster name" | sed -E 's/.*Cluster name[[:space:]]*:[[:space:]]*([^[:space:]]+).*/\1/i' | head -1)
        if [ -z "$EXISTING_NAME" ]; then
          EXISTING_NAME="unknown"
        fi
        echo "Cluster already exists in Proxmox: $EXISTING_NAME"
        echo "Skipping cluster creation (safe: will not attempt to recreate existing cluster)"
        exit 0
      fi
      
      if [ "$CLUSTER_STATUS" = "none" ]; then
        echo "Creating cluster: ${self.triggers.cluster_name}"
        ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
          "pvecm create ${self.triggers.cluster_name}" 2>&1 || {
          echo "ERROR: Failed to create cluster. Check logs for details."
          exit 1
        }
        echo "Cluster ${self.triggers.cluster_name} created successfully"
      else
        echo "WARNING: Unexpected cluster status: $CLUSTER_STATUS"
        exit 1
      fi
    EOT
  }
}

resource "null_resource" "cluster_join" {
  count = var.join_node != "" ? 1 : 0

  triggers = {
    join_node   = var.join_node
    cluster_ip  = var.cluster_ip
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Join node to cluster
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvecm add ${self.triggers.cluster_ip}" || echo "Node may already be in cluster"
    EOT
  }
}

resource "null_resource" "ha_group" {
  count = var.ha_enabled ? 1 : 0

  triggers = {
    group_name  = var.ha_group_name
    nodes       = join(",", var.ha_nodes)
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Create HA group
      # Convert comma-separated nodes to space-separated for pvesh
      NODE_LIST=$(echo "${self.triggers.nodes}" | tr ',' ' ')
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh create /cluster/ha/groups --group '${self.triggers.group_name}' --nodes $NODE_LIST" 2>&1
      
      PVE_EXIT=$?
      if [ $PVE_EXIT -eq 0 ]; then
        echo "HA group ${self.triggers.group_name} created successfully"
      else
        echo "ERROR: Failed to create HA group ${self.triggers.group_name} (exit code: $PVE_EXIT)"
        exit 1
      fi
    EOT
  }
}

resource "null_resource" "corosync_tune" {
  count = var.corosync_tune ? 1 : 0

  triggers = {
    token_timeout = var.corosync_token_timeout
    join_timeout  = var.corosync_join_timeout
    pm_ssh_host   = var.pm_ssh_host
    pm_ssh_user   = var.pm_ssh_user
    pm_ssh_key    = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Tune Corosync
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvecm set -token ${self.triggers.token_timeout} -join ${self.triggers.join_timeout}"
    EOT
  }
}
