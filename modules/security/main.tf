# Security management using pveum CLI
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
      # Check if user exists (check if the command succeeds and returns valid JSON)
      USER_CHECK_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh get /access/users/${self.triggers.userid} --output-format json 2>&1")
      USER_CHECK_EXIT=$?
      USER_EXISTS=$(echo "$USER_CHECK_OUTPUT" | jq -e . >/dev/null 2>&1 && echo "yes" || echo "no")

      if [ "$USER_EXISTS" != "yes" ] || [ $USER_CHECK_EXIT -ne 0 ]; then
        echo "ERROR: User ${self.triggers.userid} does not exist. Cannot assign RBAC role."
        exit 1
      fi

      # Configure RBAC using pveum acl modify (Proxmox CLI method)
      ACL_CMD="pveum acl modify / --roles ${self.triggers.role} --users ${self.triggers.userid}"

      ACL_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$ACL_CMD" 2>&1)
      ACL_EXIT=$?

      if [ $ACL_EXIT -eq 0 ]; then
        echo "RBAC role ${self.triggers.role} assigned successfully to user ${self.triggers.userid}"
      else
        echo "ERROR: Failed to assign RBAC role (exit code $ACL_EXIT): $ACL_OUTPUT"
        exit 1
      fi
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
      # Check if user exists (check if the command succeeds and returns valid JSON)
      USER_CHECK_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh get /access/users/${self.triggers.userid} --output-format json 2>&1")
      USER_CHECK_EXIT=$?
      USER_EXISTS=$(echo "$USER_CHECK_OUTPUT" | jq -e . >/dev/null 2>&1 && echo "yes" || echo "no")

      if [ "$USER_EXISTS" != "yes" ] || [ $USER_CHECK_EXIT -ne 0 ]; then
        echo "ERROR: User ${self.triggers.userid} does not exist. Cannot create API token."
        exit 1
      fi

      # Check if token already exists (idempotency) using pveum
      # First, get the token list and verify it's valid JSON
      TOKEN_LIST_RAW=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pveum user token list ${self.triggers.userid} --output-format json 2>&1")
      TOKEN_LIST_EXIT=$?
      
      # Only parse with jq if we got valid JSON (check if jq can parse it)
      if [ $TOKEN_LIST_EXIT -eq 0 ] && echo "$TOKEN_LIST_RAW" | jq -e . >/dev/null 2>&1; then
        TOKEN_CHECK_OUTPUT=$(echo "$TOKEN_LIST_RAW" | jq -r ".[] | select(.tokenid == \"${self.triggers.tokenid}\") | .tokenid" 2>/dev/null || echo "")
        TOKEN_EXISTS=$(if [ -n "$TOKEN_CHECK_OUTPUT" ] && [ "$TOKEN_CHECK_OUTPUT" = "${self.triggers.tokenid}" ]; then echo "yes"; else echo "no"; fi)
      else
        # If pveum failed or returned invalid JSON, assume token doesn't exist
        TOKEN_EXISTS="no"
        TOKEN_CHECK_OUTPUT=""
      fi
      
      if [ "$TOKEN_EXISTS" = "yes" ] && [ $TOKEN_LIST_EXIT -eq 0 ]; then
        echo "API token ${self.triggers.tokenid} for user ${self.triggers.userid} already exists, skipping creation"
        exit 0
      fi
      
      # Create API token using pveum (recommended method)
      EXPIRE_DAYS=${self.triggers.expire}
      echo "Creating API token ${self.triggers.tokenid} for user ${self.triggers.userid} with expiration in $EXPIRE_DAYS days..."
      
      PVEUM_CMD="pveum user token add ${self.triggers.userid} ${self.triggers.tokenid} --expire $EXPIRE_DAYS"

      PVEUM_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$PVEUM_CMD" 2>&1)
      PVEUM_EXIT=$?

      if [ $PVEUM_EXIT -eq 0 ]; then
        echo "API token ${self.triggers.tokenid} created successfully"
      else
        echo "ERROR: Failed to create API token ${self.triggers.tokenid} (exit code: $PVEUM_EXIT): $PVEUM_OUTPUT"
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
