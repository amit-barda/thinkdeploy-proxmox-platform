# Snapshot management using pvesh CLI
resource "null_resource" "snapshot" {
  count = var.enabled ? 1 : 0

  triggers = {
    node        = var.node
    vmid        = var.vmid
    snapname    = var.snapname
    description = var.description
    vm_type     = var.vm_type
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      
      echo "=== Snapshot Creation Script Started ==="
      echo "VMID: ${self.triggers.vmid}"
      echo "Snapshot name: ${self.triggers.snapname}"
      echo "VM type: ${self.triggers.vm_type}"
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
      
      # Check if snapshot already exists (idempotency)
      echo "Checking if snapshot ${self.triggers.snapname} already exists for ${self.triggers.vm_type} ${self.triggers.vmid}..."
      if [ "${self.triggers.vm_type}" = "qemu" ]; then
        SNAP_CHECK_CMD="qm listsnapshot ${self.triggers.vmid} 2>&1 | grep -q '^${self.triggers.snapname}' || echo 'NOT_FOUND'"
      else
        SNAP_CHECK_CMD="pct listsnapshot ${self.triggers.vmid} 2>&1 | grep -q '^${self.triggers.snapname}' || echo 'NOT_FOUND'"
      fi
      
      set +e  # Temporarily disable exit on error for snapshot check
      SNAP_EXISTS_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$SNAP_CHECK_CMD" 2>&1)
      SNAP_CHECK_EXIT=$?
      set -e  # Re-enable exit on error
      
      if [ "$SNAP_EXISTS_OUTPUT" != "NOT_FOUND" ] && [ $SNAP_CHECK_EXIT -eq 0 ]; then
        echo "Snapshot ${self.triggers.snapname} already exists for ${self.triggers.vm_type} ${self.triggers.vmid}"
        echo "Verifying snapshot is accessible..."
        if [ "${self.triggers.vm_type}" = "qemu" ]; then
          SNAP_VERIFY_CMD="qm listsnapshot ${self.triggers.vmid} 2>&1 | grep '^${self.triggers.snapname}'"
        else
          SNAP_VERIFY_CMD="pct listsnapshot ${self.triggers.vmid} 2>&1 | grep '^${self.triggers.snapname}'"
        fi
        set +e
        SNAP_VERIFY_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$SNAP_VERIFY_CMD" 2>&1)
        SNAP_VERIFY_EXIT=$?
        set -e
        if [ $SNAP_VERIFY_EXIT -eq 0 ] && [ -n "$SNAP_VERIFY_OUTPUT" ]; then
          echo "Snapshot verified: exists and accessible"
          exit 0
        else
          echo "WARNING: Snapshot check returned success but verification failed"
          echo "Proceeding with creation attempt..."
        fi
      else
        echo "Snapshot ${self.triggers.snapname} does not exist (check exit code: $SNAP_CHECK_EXIT)"
      fi
      
      echo "Proceeding with snapshot creation..."
      
      # Create snapshot using qm/pct command
      SNAP_DESC="${self.triggers.description}"
      if [ -n "$SNAP_DESC" ] && [ "$SNAP_DESC" != "null" ] && [ "$SNAP_DESC" != "" ]; then
        DESC_PARAM="--description '$SNAP_DESC'"
      else
        DESC_PARAM=""
      fi
      
      if [ "${self.triggers.vm_type}" = "qemu" ]; then
        SNAP_CMD="qm snapshot ${self.triggers.vmid} ${self.triggers.snapname} $DESC_PARAM"
      else
        SNAP_CMD="pct snapshot ${self.triggers.vmid} ${self.triggers.snapname} $DESC_PARAM"
      fi
      
      echo "Executing: $SNAP_CMD"
      
      # Run snapshot command via SSH
      SNAP_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$SNAP_CMD" 2>&1)
      SNAP_EXIT=$?
      
      # Always show output
      echo "Snapshot command output:"
      echo "$SNAP_OUTPUT"
      
      if [ $SNAP_EXIT -eq 0 ]; then
        echo "Snapshot ${self.triggers.snapname} created successfully for ${self.triggers.vm_type} ${self.triggers.vmid}"
        # Wait a moment for snapshot to be registered
        echo "Waiting 2 seconds for snapshot to be registered..."
        sleep 2
        
        # Verify snapshot was actually created
        echo "Verifying snapshot was created..."
        if [ "${self.triggers.vm_type}" = "qemu" ]; then
          SNAP_VERIFY_CMD="qm listsnapshot ${self.triggers.vmid} 2>&1 | grep '^${self.triggers.snapname}'"
        else
          SNAP_VERIFY_CMD="pct listsnapshot ${self.triggers.vmid} 2>&1 | grep '^${self.triggers.snapname}'"
        fi
        set +e
        SNAP_VERIFY_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$SNAP_VERIFY_CMD" 2>&1)
        SNAP_VERIFY_EXIT=$?
        set -e
        
        if [ $SNAP_VERIFY_EXIT -eq 0 ] && [ -n "$SNAP_VERIFY_OUTPUT" ]; then
          echo "✅ Snapshot ${self.triggers.snapname} verified: created and accessible"
          echo "Snapshot details:"
          echo "$SNAP_VERIFY_OUTPUT"
        else
          echo "⚠️  WARNING: Snapshot creation reported success but verification failed"
          echo "Snapshot verify exit code: $SNAP_VERIFY_EXIT"
          echo "Snapshot verify output: $SNAP_VERIFY_OUTPUT"
          echo "Snapshot may still be creating, but verification failed"
        fi
      else
        echo "❌ ERROR: Failed to create snapshot ${self.triggers.snapname} (exit code: $SNAP_EXIT)"
        echo "Snapshot error output:"
        echo "$SNAP_OUTPUT"
        echo ""
        echo "Troubleshooting information:"
        echo "  Node: ${self.triggers.node}"
        echo "  VMID: ${self.triggers.vmid}"
        echo "  VM type: ${self.triggers.vm_type}"
        echo "  Snapshot name: ${self.triggers.snapname}"
        echo "  SSH Host: ${self.triggers.pm_ssh_host}"
        echo "  SSH User: ${self.triggers.pm_ssh_user}"
        exit 1
      fi
      
      echo "=== Snapshot Creation Script Completed ==="
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      
      echo "=== Snapshot Deletion Script Started ==="
      echo "VMID: ${self.triggers.vmid}"
      echo "Snapshot name: ${self.triggers.snapname}"
      echo "VM type: ${self.triggers.vm_type}"
      
      # Delete snapshot using qm/pct command
      if [ "${self.triggers.vm_type}" = "qemu" ]; then
        DELETE_CMD="qm delsnapshot ${self.triggers.vmid} ${self.triggers.snapname}"
      else
        DELETE_CMD="pct delsnapshot ${self.triggers.vmid} ${self.triggers.snapname}"
      fi
      
      echo "Executing: $DELETE_CMD"
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$DELETE_CMD" || true
      echo "Snapshot deletion completed (or snapshot did not exist)"
      echo "=== Snapshot Deletion Script Completed ==="
    EOT
  }
}
