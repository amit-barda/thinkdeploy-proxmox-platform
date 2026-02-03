# LXC container management using pvesh CLI
resource "null_resource" "lxc" {
  count = var.enabled ? 1 : 0

  triggers = {
    node        = var.node
    vmid        = var.vmid
    cores       = var.cores
    memory      = var.memory
    rootfs      = var.rootfs
    storage     = var.storage
    ostemplate  = var.ostemplate
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      
      echo "=== LXC Container Creation Script Started ==="
      echo "VMID: ${self.triggers.vmid}"
      echo "Node: ${self.triggers.node}"
      echo "SSH Host: ${self.triggers.pm_ssh_host}"
      echo "SSH User: ${self.triggers.pm_ssh_user}"
      echo "SSH Key: ${self.triggers.pm_ssh_key}"
      
      # Verify SSH key exists
      if [ ! -f "${self.triggers.pm_ssh_key}" ]; then
        echo "ERROR: SSH key file not found: ${self.triggers.pm_ssh_key}"
        exit 1
      fi
      echo "SSH key verified: ${self.triggers.pm_ssh_key}"
      
      # Test SSH connectivity first
      echo "Testing SSH connectivity..."
      SSH_TEST=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "echo 'SSH OK'" 2>&1)
      SSH_TEST_EXIT=$?
      if [ $SSH_TEST_EXIT -ne 0 ]; then
        echo "ERROR: SSH connection failed to ${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}"
        echo "SSH error output: $SSH_TEST"
        exit 1
      fi
      echo "SSH connectivity verified: $SSH_TEST"
      
      # Check if LXC container already exists (idempotency)
      echo "Checking if LXC container ${self.triggers.vmid} already exists on node ${self.triggers.node}..."
      LXC_CHECK_CMD="pvesh get /nodes/${self.triggers.node}/lxc/${self.triggers.vmid}/status/current --output-format json 2>&1"
      set +e  # Temporarily disable exit on error for LXC check (LXC may not exist)
      LXC_EXISTS_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$LXC_CHECK_CMD" 2>&1)
      LXC_CHECK_EXIT=$?
      set -e  # Re-enable exit on error
      LXC_EXISTS=$(echo "$LXC_EXISTS_OUTPUT" | jq -r '.status // empty' 2>/dev/null || echo "")
      
      if [ "$LXC_CHECK_EXIT" -eq 0 ] && [ -n "$LXC_EXISTS" ] && [ "$LXC_EXISTS" != "null" ] && [ "$LXC_EXISTS" != "" ]; then
        echo "LXC container ${self.triggers.vmid} already exists on node ${self.triggers.node} (status: $LXC_EXISTS)"
        echo "Verifying LXC container is accessible..."
        # Use /config endpoint to get LXC configuration
        LXC_VERIFY_CMD="pvesh get /nodes/${self.triggers.node}/lxc/${self.triggers.vmid}/config --output-format json 2>&1"
        set +e  # Temporarily disable exit on error for LXC verify
        LXC_VERIFY_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$LXC_VERIFY_CMD" 2>&1)
        LXC_VERIFY_EXIT=$?
        set -e  # Re-enable exit on error
        # If config endpoint returns successfully, LXC exists
        if [ "$LXC_VERIFY_EXIT" -eq 0 ]; then
          echo "LXC container verified: exists and accessible (vmid: ${self.triggers.vmid})"
          exit 0
        else
          echo "WARNING: LXC check returned status but verification failed"
          echo "LXC verify output: $LXC_VERIFY_OUTPUT"
          echo "Proceeding with creation attempt..."
        fi
      else
        echo "LXC container ${self.triggers.vmid} does not exist (check exit code: $LXC_CHECK_EXIT, output: $LXC_EXISTS_OUTPUT)"
      fi
      
      echo "Proceeding with LXC container creation..."
      
      # Create LXC container using pvesh
      # Convert rootfs size (e.g., 20G) to format expected by pvesh
      # Format: storage:size (size in MB, or use G/M suffix)
      ROOTFS_SIZE="${self.triggers.rootfs}"
      # If size ends with G, convert to MB (multiply by 1024)
      if [[ "$ROOTFS_SIZE" =~ ^[0-9]+G$ ]]; then
        SIZE_MB=$(echo "$ROOTFS_SIZE" | sed 's/G$//' | awk '{print $1 * 1024}')
        ROOTFS_PARAM="${self.triggers.storage}:$SIZE_MB"
      elif [[ "$ROOTFS_SIZE" =~ ^[0-9]+M$ ]]; then
        SIZE_MB=$(echo "$ROOTFS_SIZE" | sed 's/M$//')
        ROOTFS_PARAM="${self.triggers.storage}:$SIZE_MB"
      else
        # Assume it's already in MB
        ROOTFS_PARAM="${self.triggers.storage}:$ROOTFS_SIZE"
      fi
      
      echo "LXC Creation Parameters:"
      echo "  VMID: ${self.triggers.vmid}"
      echo "  Node: ${self.triggers.node}"
      echo "  Cores: ${self.triggers.cores}"
      echo "  Memory: ${self.triggers.memory} MB"
      echo "  RootFS: $ROOTFS_PARAM"
      echo "  OSTemplate: ${self.triggers.ostemplate}"
      echo "  Storage: ${self.triggers.storage}"
      
      # Build pvesh command
      PVE_CMD="pvesh create /nodes/${self.triggers.node}/lxc --vmid ${self.triggers.vmid} --hostname lxc-${self.triggers.vmid} --ostemplate '${self.triggers.ostemplate}' --cores ${self.triggers.cores} --memory ${self.triggers.memory} --rootfs '$ROOTFS_PARAM' --net0 name=eth0,bridge=vmbr0,ip=dhcp"
      echo "Executing: $PVE_CMD"
      
      # Run pvesh create command and capture both stdout and stderr
      PVE_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$PVE_CMD" 2>&1)
      PVE_EXIT=$?
      
      # Always show output
      echo "pvesh create output:"
      echo "$PVE_OUTPUT"
      
      if [ $PVE_EXIT -eq 0 ]; then
        echo "pvesh create command succeeded (exit code: 0)"
        # Wait a moment for LXC to be registered
        echo "Waiting 3 seconds for LXC container to be registered..."
        sleep 3
        
        # Verify LXC was actually created
        echo "Verifying LXC container was created..."
        LXC_VERIFY_CMD="pvesh get /nodes/${self.triggers.node}/lxc/${self.triggers.vmid}/config --output-format json 2>&1"
        set +e  # Temporarily disable exit on error for LXC verify
        LXC_VERIFY_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$LXC_VERIFY_CMD" 2>&1)
        LXC_VERIFY_EXIT=$?
        set -e  # Re-enable exit on error
        
        if [ "$LXC_VERIFY_EXIT" -eq 0 ]; then
          echo "✅ LXC container ${self.triggers.vmid} verified: created and accessible"
          echo "LXC details:"
          echo "$LXC_VERIFY_OUTPUT" | jq '.' 2>/dev/null || echo "$LXC_VERIFY_OUTPUT"
        else
          echo "⚠️  WARNING: LXC creation reported success but verification failed"
          echo "LXC verify exit code: $LXC_VERIFY_EXIT"
          echo "LXC verify output: $LXC_VERIFY_OUTPUT"
          echo "LXC may still be creating, but verification failed"
        fi
      else
        echo "❌ ERROR: Failed to create LXC container ${self.triggers.vmid} (exit code: $PVE_EXIT)"
        echo "pvesh error output:"
        echo "$PVE_OUTPUT"
        echo ""
        echo "Troubleshooting information:"
        echo "  Node: ${self.triggers.node}"
        echo "  VMID: ${self.triggers.vmid}"
        echo "  Storage: ${self.triggers.storage}"
        echo "  RootFS parameter: $ROOTFS_PARAM"
        echo "  OSTemplate: ${self.triggers.ostemplate}"
        echo "  SSH Host: ${self.triggers.pm_ssh_host}"
        echo "  SSH User: ${self.triggers.pm_ssh_user}"
        exit 1
      fi
      
      echo "=== LXC Container Creation Script Completed ==="
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Delete LXC container via SSH + pvesh
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh delete /nodes/${self.triggers.node}/lxc/${self.triggers.vmid}" || true
    EOT
  }
}
