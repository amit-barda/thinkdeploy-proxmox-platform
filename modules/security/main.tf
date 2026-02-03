# Security management using pvesh CLI
resource "null_resource" "rbac_role" {
  for_each = var.rbac_roles

  triggers = {
    userid      = each.value.userid
    role        = each.value.role
    privileges  = join(",", each.value.privileges)
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Configure RBAC
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh create /access/users/${self.triggers.userid} --groups '${self.triggers.role}'" 2>&1 || echo "User may already exist or group assignment failed"
    EOT
  }
}

resource "null_resource" "api_token" {
  for_each = var.api_tokens

  triggers = {
    userid      = each.value.userid
    tokenid     = each.value.tokenid
    expire      = each.value.expire
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Check if token already exists (idempotency)
      TOKEN_EXISTS=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh get /access/users/${self.triggers.userid}/token/${self.triggers.tokenid} --output-format json 2>/dev/null" | jq -r '.tokenid // empty' 2>/dev/null || echo "")
      
      if [ -n "$TOKEN_EXISTS" ] && [ "$TOKEN_EXISTS" != "null" ]; then
        echo "API token ${self.triggers.tokenid} for user ${self.triggers.userid} already exists, skipping creation"
        exit 0
      fi
      
      # Create API token
      echo "Creating API token ${self.triggers.tokenid} for user ${self.triggers.userid}..."
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh create /access/users/${self.triggers.userid}/token/${self.triggers.tokenid} --expire '${self.triggers.expire}'" 2>&1
      
      PVE_EXIT=$?
      if [ $PVE_EXIT -eq 0 ]; then
        echo "API token ${self.triggers.tokenid} created successfully"
      else
        echo "ERROR: Failed to create API token ${self.triggers.tokenid} (exit code: $PVE_EXIT)"
        exit 1
      fi
    EOT
  }
}

resource "null_resource" "ssh_hardening" {
  count = var.ssh_hardening_enabled ? 1 : 0

  triggers = {
    permit_root   = var.ssh_permit_root
    password_auth = var.ssh_password_auth
    max_tries     = var.ssh_max_tries
    pm_ssh_host   = var.pm_ssh_host
    pm_ssh_user   = var.pm_ssh_user
    pm_ssh_key    = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      # SSH hardening
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "sed -i 's/#PermitRootLogin.*/PermitRootLogin ${self.triggers.permit_root}/' /etc/ssh/sshd_config && \
         sed -i 's/#PasswordAuthentication.*/PasswordAuthentication ${self.triggers.password_auth}/' /etc/ssh/sshd_config && \
         sed -i 's/#MaxAuthTries.*/MaxAuthTries ${self.triggers.max_tries}/' /etc/ssh/sshd_config && \
         systemctl restart sshd" || echo "SSH config may already be set"
    EOT
  }
}

resource "null_resource" "firewall_policy" {
  count = var.firewall_policy_enabled ? 1 : 0

  triggers = {
    default_policy = var.firewall_default_policy
    log_level      = var.firewall_log_level
    pm_ssh_host    = var.pm_ssh_host
    pm_ssh_user    = var.pm_ssh_user
    pm_ssh_key     = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Configure firewall policy
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh set /cluster/firewall/options --policy ${self.triggers.default_policy} --log_level ${self.triggers.log_level}"
    EOT
  }
}
