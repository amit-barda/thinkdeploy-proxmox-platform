# Autoscaling module that integrates with Proxmox autoscaling tools
# Supports: proxmox-vm-autoscale, proxmox-lxc-autoscale, proxmox-cluster-balancer
resource "null_resource" "autoscaling" {
  count = var.enabled ? 1 : 0

  triggers = {
    group                    = var.group
    min                      = var.min
    max                      = var.max
    scale_up                 = var.scale_up
    scale_down               = var.scale_down
    resource_type            = var.resource_type
    install_path             = var.install_path
    pm_ssh_host              = var.pm_ssh_host
    pm_ssh_user              = var.pm_ssh_user
    pm_ssh_key               = var.pm_ssh_private_key_path
    vm_autoscale_repo        = var.vm_autoscale_repo
    lxc_autoscale_repo       = var.lxc_autoscale_repo
    cluster_balancer_repo    = var.cluster_balancer_repo
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      
      echo "=== Autoscaling Setup Started ==="
      echo "Group: ${self.triggers.group}"
      echo "Resource Type: ${self.triggers.resource_type}"
      echo "Min: ${self.triggers.min}, Max: ${self.triggers.max}"
      echo "Scale-up: ${self.triggers.scale_up}%, Scale-down: ${self.triggers.scale_down}%"
      echo "Install Path: ${self.triggers.install_path}"
      
      # Verify SSH key exists
      if [ ! -f "${self.triggers.pm_ssh_key}" ]; then
        echo "ERROR: SSH key file not found: ${self.triggers.pm_ssh_key}"
        exit 1
      fi
      
      # Test SSH connectivity
      echo "Testing SSH connectivity..."
      if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${self.triggers.pm_ssh_key}" \
        "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "echo 'SSH OK'" > /dev/null 2>&1; then
        echo "ERROR: SSH connection failed to ${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}"
        exit 1
      fi
      echo "SSH connectivity verified"
      
      # Determine which repository to use based on resource type
      if [ "${self.triggers.resource_type}" = "vm" ]; then
        REPO_URL="${self.triggers.vm_autoscale_repo}"
        TOOL_NAME="proxmox-vm-autoscale"
      elif [ "${self.triggers.resource_type}" = "lxc" ]; then
        REPO_URL="${self.triggers.lxc_autoscale_repo}"
        TOOL_NAME="proxmox-lxc-autoscale"
      else
        echo "ERROR: Unknown resource type: ${self.triggers.resource_type}"
        exit 1
      fi
      
      echo "Installing $TOOL_NAME from $REPO_URL..."
      
      # Install autoscaling tool on Proxmox node
      INSTALL_SCRIPT=$(cat <<'INSTALL_EOF'
        set -euo pipefail
        
        INSTALL_PATH="$1"
        REPO_URL="$2"
        TOOL_NAME="$3"
        GROUP="$4"
        MIN="$5"
        MAX="$6"
        SCALE_UP="$7"
        SCALE_DOWN="$8"
        
        # Create installation directory
        mkdir -p "$INSTALL_PATH"
        cd "$INSTALL_PATH"
        
        # Clone repository if it doesn't exist
        if [ ! -d "$TOOL_NAME" ]; then
          echo "Cloning $TOOL_NAME..."
          git clone "$REPO_URL" "$TOOL_NAME" || {
            echo "ERROR: Failed to clone $REPO_URL"
            exit 1
          }
        else
          echo "Repository $TOOL_NAME already exists, updating..."
          cd "$TOOL_NAME"
          git pull || echo "Warning: git pull failed, continuing with existing code"
          cd ..
        fi
        
        # Check if tool has requirements.txt or setup script
        cd "$TOOL_NAME"
        if [ -f "requirements.txt" ]; then
          echo "Installing Python dependencies..."
          pip3 install -r requirements.txt || {
            echo "Warning: Failed to install some dependencies, continuing..."
          }
        fi
        
        if [ -f "setup.sh" ]; then
          echo "Running setup script..."
          bash setup.sh || {
            echo "Warning: Setup script had issues, continuing..."
          }
        fi
        
        # Create configuration file for this autoscaling group
        CONFIG_DIR="$INSTALL_PATH/config"
        mkdir -p "$CONFIG_DIR"
        
        CONFIG_FILE="$CONFIG_DIR/${GROUP}.json"
        cat > "$CONFIG_FILE" <<CONFIG_EOF
{
  "group": "$GROUP",
  "min": $MIN,
  "max": $MAX,
  "scale_up": $SCALE_UP,
  "scale_down": $SCALE_DOWN
}
CONFIG_EOF
        
        echo "Configuration saved to $CONFIG_FILE"
        
        # Check if systemd service file exists in the tool
        if [ -f "autoscale.service" ] || [ -f "$TOOL_NAME.service" ]; then
          SERVICE_FILE=$(find . -name "*.service" | head -1)
          if [ -n "$SERVICE_FILE" ]; then
            echo "Found service file: $SERVICE_FILE"
            # Copy service file and enable it
            sudo cp "$SERVICE_FILE" "/etc/systemd/system/${TOOL_NAME}-${GROUP}.service" || {
              echo "Warning: Failed to install service file (may need root)"
            }
            sudo systemctl daemon-reload || true
            sudo systemctl enable "${TOOL_NAME}-${GROUP}.service" || true
            echo "Service ${TOOL_NAME}-${GROUP} configured"
          fi
        fi
        
        echo "Installation completed for $TOOL_NAME"
INSTALL_EOF
      )
      
      # Execute installation script on Proxmox node
      echo "$INSTALL_SCRIPT" | ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" \
        "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "bash -s --" \
        "${self.triggers.install_path}" \
        "$REPO_URL" \
        "$TOOL_NAME" \
        "${self.triggers.group}" \
        "${self.triggers.min}" \
        "${self.triggers.max}" \
        "${self.triggers.scale_up}" \
        "${self.triggers.scale_down}"
      
      INSTALL_EXIT=$?
      
      if [ $INSTALL_EXIT -ne 0 ]; then
        echo "ERROR: Autoscaling installation failed (exit code: $INSTALL_EXIT)"
        exit 1
      fi
      
      echo "✅ Autoscaling setup completed successfully"
      echo "=== Autoscaling Setup Completed ==="
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      
      echo "Removing autoscaling configuration for group: ${self.triggers.group}"
      
      # Remove service if it exists
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" \
        "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "sudo systemctl stop ${self.triggers.resource_type}-autoscale-${self.triggers.group}.service 2>/dev/null || true; \
         sudo systemctl disable ${self.triggers.resource_type}-autoscale-${self.triggers.group}.service 2>/dev/null || true; \
         sudo rm -f /etc/systemd/system/${self.triggers.resource_type}-autoscale-${self.triggers.group}.service 2>/dev/null || true; \
         sudo systemctl daemon-reload 2>/dev/null || true"
      
      echo "Autoscaling cleanup completed"
    EOT
  }
}
