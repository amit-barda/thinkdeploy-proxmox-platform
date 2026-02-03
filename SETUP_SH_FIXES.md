# setup.sh Logic Bug Fixes

## Issues Fixed

1. **Missing call to configure_proxmox_connection()** - Function defined but never called
2. **Deploy All only deploys when VMs exist** - Should deploy any configured resources (storage/networking/security/backup) even with zero VMs
3. **SSH key path ~ expansion inconsistency** - Some places expand ~, others don't
4. **Undefined variable CLUSTER_EXISTS** - Should be PROXMOX_CLUSTER_EXISTS

## Unified Diff

```diff
--- a/setup.sh
+++ b/setup.sh
@@ -929,6 +929,10 @@
 # Main configuration workflow
 log "Starting infrastructure configuration workflow..."
 
+# Configure Proxmox connection if not already set via environment
+if [ -z "${TF_VAR_pm_api_url:-}" ] || [ -z "${TF_VAR_pm_user:-}" ] || [ -z "${TF_VAR_pm_password:-}" ]; then
+    configure_proxmox_connection
+fi
+
 # Main loop
 # Note: Proxmox connection variables should be set via environment variables or terraform.tfvars
 # (pm_api_url, pm_user, pm_password, pm_ssh_host, pm_ssh_user, pm_ssh_private_key_path)
@@ -1263,6 +1267,7 @@
     SSH_HOST="${TF_VAR_pm_ssh_host:-localhost}"
     SSH_USER="${TF_VAR_pm_ssh_user:-root}"
     SSH_KEY="${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}"
+    SSH_KEY="${SSH_KEY/#\~/$HOME}"
     
     if [ "$PROXMOX_CLI_METHOD" = "pvesh" ]; then
         # CRITICAL: Force JSON output - pvesh defaults to TABLE format
@@ -1449,7 +1454,7 @@
                                     if [ $JQ_EXIT -ne 0 ]; then
                                         log "ERROR: Failed to update CLUSTER_JSON with jq (exit code: $JQ_EXIT)" 1>&2
                                     else
-                                        log "Successfully updated CLUSTER_JSON (create_cluster=$([ "$CLUSTER_EXISTS" = "yes" ] && echo "false" || echo "true"))" 1>&2
+                                        log "Successfully updated CLUSTER_JSON (create_cluster=$([ "$PROXMOX_CLUSTER_EXISTS" = "true" ] && echo "false" || echo "true"))" 1>&2
                                     fi
                                 else
                                     log "WARNING: cluster_name or primary_node is empty, skipping" 1>&2
@@ -1627,11 +1632,11 @@
         # Count enabled VMs
         enabled_vms=$(jq -r '.vms // {} | to_entries | map(select(.value.enabled==true)) | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
         log "DEBUG DeployAll: TFVARS_FILE=$TFVARS_FILE enabled_vms=$enabled_vms TF_ROOT=$TF_ROOT"
         
-        if [ "$enabled_vms" -gt 0 ]; then
+        if [ "$HAS_CONFIGS" = "true" ]; then
             run_terraform_deploy "$TFVARS_FILE"
             # Exit after successful deployment
             exit 0
         else
-            error_exit "Deploy All selected but no enabled VMs found in tfvars ($TFVARS_FILE)"
+            error_exit "Deploy All selected but no configurations found in tfvars ($TFVARS_FILE)"
         fi
     fi
     
@@ -1993,7 +1998,9 @@
     # Check SSH connectivity
     if [ -n "${TF_VAR_pm_ssh_host:-}" ] && [ -n "${TF_VAR_pm_ssh_user:-}" ]; then
         log "Testing SSH connectivity to ${TF_VAR_pm_ssh_user}@${TF_VAR_pm_ssh_host}..."
-        if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}" \
+        SSH_KEY_CHECK="${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}"
+        SSH_KEY_CHECK="${SSH_KEY_CHECK/#\~/$HOME}"
+        if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY_CHECK" \
             "${TF_VAR_pm_ssh_user}@${TF_VAR_pm_ssh_host}" "echo 'SSH OK'" > /dev/null 2>&1; then
             error_exit "SSH connection to ${TF_VAR_pm_ssh_user}@${TF_VAR_pm_ssh_host} failed. Check SSH key and connectivity."
         fi
@@ -2053,8 +2060,9 @@
                     NODE=$(echo "{$vms}{$lxcs}" | jq -r ".[] | select(.vmid == $vmid) | .node" 2>/dev/null | head -1)
                     if [ -n "$NODE" ]; then
                         # Check if VMID exists
-                        EXISTING=$(ssh -o StrictHostKeyChecking=no -i "${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}" \
-                            "${TF_VAR_pm_ssh_user:-root}@${TF_VAR_pm_ssh_host:-localhost}" \
+                        SSH_KEY_VMID="${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}"
+                        SSH_KEY_VMID="${SSH_KEY_VMID/#\~/$HOME}"
+                        EXISTING=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_VMID" \
+                            "${TF_VAR_pm_ssh_user:-root}@${TF_VAR_pm_ssh_host:-localhost}" \
                             "pvesh get /nodes/$NODE/qemu/$vmid 2>/dev/null || pvesh get /nodes/$NODE/lxc/$vmid 2>/dev/null" 2>/dev/null | wc -l)
                         if [ "$EXISTING" -gt 0 ]; then
                             warning "VMID $vmid already exists on node $NODE"
@@ -2078,8 +2086,9 @@
                     # Get first node
                     NODE=$(echo "{$vms}{$lxcs}" | jq -r ".[] | select(.storage == \"$storage\") | .node" 2>/dev/null | head -1)
                     if [ -n "$NODE" ]; then
-                        if ! ssh -o StrictHostKeyChecking=no -i "${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}" \
-                            "${TF_VAR_pm_ssh_user:-root}@${TF_VAR_pm_ssh_host:-localhost}" \
+                        SSH_KEY_STORAGE="${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}"
+                        SSH_KEY_STORAGE="${SSH_KEY_STORAGE/#\~/$HOME}"
+                        if ! ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_STORAGE" \
+                            "${TF_VAR_pm_ssh_user:-root}@${TF_VAR_pm_ssh_host:-localhost}" \
                             "pvesh get /nodes/$NODE/storage/$storage/status" > /dev/null 2>&1; then
                             warning "Storage '$storage' not found on node $NODE"
                             echo "⚠️  Storage '$storage' validation failed" 1>&2
@@ -2223,7 +2232,7 @@
     log "DEBUG DeployAll: Checking enabled VMs before deploy: $enabled_vms_check"
     echo "🔍 Checking deployment requirements..." 1>&2
     
-    if [ "$enabled_vms_check" -gt 0 ]; then
+    if [ "$HAS_CONFIGS" = "true" ]; then
         log "DEBUG DeployAll: enabled_vms=$enabled_vms_check > 0, calling run_terraform_deploy"
         echo "🚀 Deploying $enabled_vms_check enabled VM(s)..." 1>&2
         
@@ -2235,16 +2244,8 @@
         if [ -z "${TF_EXIT_CODE:-}" ]; then
             error_exit "VMs requested but deploy skipped. run_terraform_deploy did not set TF_EXIT_CODE. This is a bug."
         fi
-    else
-        # No enabled VMs, but still deploy if other resources exist
-        if [ "$HAS_CONFIGS" = "true" ]; then
-            log "DEBUG DeployAll: No enabled VMs, but HAS_CONFIGS=true, calling run_terraform_deploy"
-            echo "🚀 Deploying other infrastructure resources..." 1>&2
-            run_terraform_deploy "$TFVARS_FILE"
-            TF_EXIT_CODE=$?
-        else
-            warning "No enabled VMs and no other configurations to deploy"
-            TF_EXIT_CODE=0
+    elif [ "$HAS_CONFIGS" = "true" ]; then
+        log "DEBUG DeployAll: No enabled VMs, but HAS_CONFIGS=true, calling run_terraform_deploy"
+        echo "🚀 Deploying other infrastructure resources..." 1>&2
+        run_terraform_deploy "$TFVARS_FILE"
+        TF_EXIT_CODE=$?
+    else
+        warning "No enabled VMs and no other configurations to deploy"
+        TF_EXIT_CODE=0
         fi
-    fi
-    
-    # FATAL: If we reach here and enabled VMs > 0 but run_terraform_deploy wasn't called
-    if [ "$enabled_vms_check" -gt 0 ] && [ -z "${TF_EXIT_CODE:-}" ]; then
-        error_exit "VMs requested but deploy skipped. This is a bug."
     fi
```

## Explanation

### Fix 1: Call configure_proxmox_connection()
**Lines 932-936**: Added check to call `configure_proxmox_connection()` if connection variables aren't set via environment. This ensures Proxmox credentials are collected before the main menu loop.

### Fix 2: Deploy All with zero VMs
**Line 1635**: Changed from `if [ "$enabled_vms" -gt 0 ]` to `if [ "$HAS_CONFIGS" = "true" ]` - now deploys any configured resources (storage/networking/security/backup/cluster) even with zero VMs.

**Line 1638**: Updated error message from "no enabled VMs" to "no configurations" to reflect the change.

**Line 2235**: Changed from `if [ "$enabled_vms_check" -gt 0 ]` to `if [ "$HAS_CONFIGS" = "true" ]` - same fix in the main deploy path.

**Lines 2237-2246**: Simplified the else branch - removed redundant nested `if [ "$HAS_CONFIGS" = "true" ]` check and the fatal error check that was checking the wrong condition.

### Fix 3: SSH key ~ expansion consistency
**Line 1270**: Expand ~ in `SSH_KEY` variable in `detect_proxmox_cluster()` function.

**Lines 2001-2002**: Expand ~ before using SSH key in preflight_checks().

**Lines 2063-2064**: Expand ~ before using SSH key for VMID check.

**Lines 2089-2090**: Expand ~ before using SSH key for storage check.

### Fix 4: Undefined variable CLUSTER_EXISTS
**Line 1457**: Changed `$CLUSTER_EXISTS` to `$PROXMOX_CLUSTER_EXISTS` (the correct variable name that's actually set).

## Testing

After applying the patch:

1. **Test Deploy All with zero VMs**: Configure only storage/networking/security, select "Deploy All" - should deploy successfully.

2. **Test Proxmox connection prompt**: Run `./setup.sh` without setting `TF_VAR_*` environment variables - should prompt for connection details.

3. **Test SSH key expansion**: Use `~/.ssh/id_rsa` as SSH key path - should work in all contexts.

4. **Test with set -u**: Script should not fail with "unbound variable" errors.
