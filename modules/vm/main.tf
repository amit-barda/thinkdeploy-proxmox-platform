2# VM management using pvesh CLI
resource "null_resource" "vm" {
  count = var.enabled ? 1 : 0

  triggers = {
    node        = var.node
    vmid        = var.vmid
    cores       = var.cores
    memory      = var.memory
    disk        = var.disk
    storage     = var.storage
    network     = var.network
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
4 cat /root/thinkdeploy-proxmox-platform/generated/thinkdeploy.auto.tfvars.json | jq '.autoscaling_config'l    force_run   = var.force_run
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      
      echo "=== VM Creation Script Started ==="
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
      
      # Check if VM already exists (idempotency)
      echo "Checking if VM ${self.triggers.vmid} already exists on node ${self.triggers.node}..."
      VM_CHECK_CMD="pvesh get /nodes/${self.triggers.node}/qemu/${self.triggers.vmid}/status/current --output-format json 2>&1"
      set +e  # Temporarily disable exit on error for VM check (VM may not exist)
      VM_EXISTS_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$VM_CHECK_CMD" 2>&1)
      VM_CHECK_EXIT=$?
      set -e  # Re-enable exit on error
      VM_EXISTS=$(echo "$VM_EXISTS_OUTPUT" | jq -r '.status // empty' 2>/dev/null || echo "")
      
      if [ "$VM_CHECK_EXIT" -eq 0 ] && [ -n "$VM_EXISTS" ] && [ "$VM_EXISTS" != "null" ] && [ "$VM_EXISTS" != "" ]; then
        echo "VM ${self.triggers.vmid} already exists on node ${self.triggers.node} (status: $VM_EXISTS)"
        echo "Verifying VM is accessible..."
        # Use /config endpoint to get VM configuration (includes vmid)
        VM_VERIFY_CMD="pvesh get /nodes/${self.triggers.node}/qemu/${self.triggers.vmid}/config --output-format json 2>&1"
        set +e  # Temporarily disable exit on error for VM verify
        VM_VERIFY_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$VM_VERIFY_CMD" 2>&1)
        VM_VERIFY_EXIT=$?
        set -e  # Re-enable exit on error
        # Extract vmid from config (it's stored as a number, not in a vmid field, so check if config exists)
        VM_VERIFY=$(echo "$VM_VERIFY_OUTPUT" | jq -r '.vmid // .[0].vmid // empty' 2>/dev/null || echo "")
        # If vmid not in config, check if we got valid config (means VM exists)
        if [ -z "$VM_VERIFY" ] && [ "$VM_VERIFY_EXIT" -eq 0 ]; then
          # Config endpoint returns VM config, so VM exists - use the trigger vmid as verification
          VM_VERIFY="${self.triggers.vmid}"
        fi
        if [ "$VM_VERIFY_EXIT" -eq 0 ] && [ -n "$VM_VERIFY" ]; then
          echo "VM verified: exists and accessible (vmid: ${self.triggers.vmid})"
          exit 0
        else
          echo "WARNING: VM check returned status but verification failed"
          echo "VM verify exit code: $VM_VERIFY_EXIT"
          echo "VM verify output: $VM_VERIFY_OUTPUT"
          echo "Proceeding with creation attempt..."
        fi
      else
        echo "VM ${self.triggers.vmid} does not exist (check exit code: $VM_CHECK_EXIT, output: $VM_EXISTS_OUTPUT)"
      fi
      
      echo "Proceeding with VM creation..."
      
      # Create VM using pvesh
      # Convert disk size (e.g., 50G) to format expected by pvesh
      DISK_SIZE="${self.triggers.disk}"
      # If size ends with G, convert to MB (multiply by 1024)
      if [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]]; then
        SIZE_MB=$(echo "$DISK_SIZE" | sed 's/G$//' | awk '{print $1 * 1024}')
        DISK_PARAM="${self.triggers.storage}:$SIZE_MB"
      elif [[ "$DISK_SIZE" =~ ^[0-9]+M$ ]]; then
        SIZE_MB=$(echo "$DISK_SIZE" | sed 's/M$//')
        DISK_PARAM="${self.triggers.storage}:$SIZE_MB"
      else
        # Assume it's already in MB
        DISK_PARAM="${self.triggers.storage}:$DISK_SIZE"
      fi
      
      echo "VM Creation Parameters:"
      echo "  VMID: ${self.triggers.vmid}"
      echo "  Node: ${self.triggers.node}"
      echo "  Cores: ${self.triggers.cores}"
      echo "  Memory: ${self.triggers.memory} MB"
      echo "  Disk: $DISK_PARAM"
      echo "  Network: ${self.triggers.network}"
      echo "  Storage: ${self.triggers.storage}"
      
      # Build pvesh command
      PVE_CMD="pvesh create /nodes/${self.triggers.node}/qemu --vmid ${self.triggers.vmid} --name vm-${self.triggers.vmid} --cores ${self.triggers.cores} --memory ${self.triggers.memory} --net0 '${self.triggers.network}' --scsi0 '$DISK_PARAM'"
      echo "Executing: $PVE_CMD"
      
      # Run pvesh create command and capture both stdout and stderr
      PVE_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$PVE_CMD" 2>&1)
      PVE_EXIT=$?
      
      # Always show output
      echo "pvesh create output:"
      echo "$PVE_OUTPUT"
      
      if [ $PVE_EXIT -eq 0 ]; then
        echo "pvesh create command succeeded (exit code: 0)"
        # Wait a moment for VM to be registered
        echo "Waiting 3 seconds for VM to be registered..."
        sleep 3
        
        # Verify VM was actually created
        echo "Verifying VM was created..."
        # Use /config endpoint to get VM configuration
        VM_VERIFY_CMD="pvesh get /nodes/${self.triggers.node}/qemu/${self.triggers.vmid}/config --output-format json 2>&1"
        set +e  # Temporarily disable exit on error for VM verify
        VM_VERIFY_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$VM_VERIFY_CMD" 2>&1)
        VM_VERIFY_EXIT=$?
        set -e  # Re-enable exit on error
        # Extract vmid from config or check if config is valid (means VM exists)
        VM_VERIFY=$(echo "$VM_VERIFY_OUTPUT" | jq -r '.vmid // empty' 2>/dev/null || echo "")
        # If config endpoint returns successfully, VM exists (even if vmid not in response)
        if [ "$VM_VERIFY_EXIT" -eq 0 ] && [ -z "$VM_VERIFY" ]; then
          # Config exists, so VM exists - use trigger vmid as verification
          VM_VERIFY="${self.triggers.vmid}"
        fi
        
        if [ "$VM_VERIFY_EXIT" -eq 0 ] && [ -n "$VM_VERIFY" ]; then
          echo "✅ VM ${self.triggers.vmid} verified: created and accessible (vmid: $VM_VERIFY)"
          echo "VM details:"
          echo "$VM_VERIFY_OUTPUT" | jq '.' 2>/dev/null || echo "$VM_VERIFY_OUTPUT"
        else
          echo "⚠️  WARNING: VM creation reported success but verification failed"
          echo "VM verify exit code: $VM_VERIFY_EXIT"
          echo "VM verify output: $VM_VERIFY_OUTPUT"
          echo "VM verify result: $VM_VERIFY"
          echo "VM may still be creating, but verification failed"
        fi
      else
        echo "❌ ERROR: Failed to create VM ${self.triggers.vmid} (exit code: $PVE_EXIT)"
        echo "pvesh error output:"
        echo "$PVE_OUTPUT"
        echo ""
        echo "Troubleshooting information:"
        echo "  Node: ${self.triggers.node}"
        echo "  VMID: ${self.triggers.vmid}"
        echo "  Storage: ${self.triggers.storage}"
        echo "  Disk parameter: $DISK_PARAM"
        echo "  Network: ${self.triggers.network}"
        echo "  SSH Host: ${self.triggers.pm_ssh_host}"
        echo "  SSH User: ${self.triggers.pm_ssh_user}"
        exit 1
      fi
      
      echo "=== VM Creation Script Completed ==="
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      echo "Deleting VM ${self.triggers.vmid} on node ${self.triggers.node}..."
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh delete /nodes/${self.triggers.node}/qemu/${self.triggers.vmid}" 2>&1 || echo "VM may already be deleted"
      echo "VM deletion completed"
    EOT
  }
}
