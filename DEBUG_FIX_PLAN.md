# ThinkDeploy Proxmox Platform - Debug Fix Plan

## Most Likely Root Causes (Ranked)

### 1. **Hardcoded "localhost" in Networking Module** (CRITICAL)
- **Location**: `modules/networking/main.tf` lines 19, 40, 64, 85
- **Problem**: All networking commands use `/nodes/localhost/network` instead of actual node name
- **Impact**: Networking configs fail on multi-node clusters or when SSH host != localhost
- **Evidence**: 
  ```bash
  # Line 19: Hardcoded localhost
  "pvesh create /nodes/localhost/network --iface ${self.triggers.bridge_name}..."
  ```
- **Fix**: Use actual node name from variables or detect from SSH host

### 2. **Missing Module Dependencies** (CRITICAL)
- **Location**: `main.tf` - no `depends_on` between modules
- **Problem**: VMs may try to create before storage/networking/cluster ready
- **Impact**: Race conditions, VM creation fails if storage not ready
- **Evidence**: No `depends_on` in any module calls in `main.tf`
- **Fix**: Add explicit `depends_on` for module ordering

### 3. **Unquoted Variables in pvesh Commands** (HIGH)
- **Location**: Multiple modules (vm/main.tf:50, lxc/main.tf:37, backup_job/main.tf:48)
- **Problem**: Variables like `$DISK_PARAM`, `$ROOTFS_PARAM`, `$STARTTIME` not quoted
- **Impact**: Commands break if values contain spaces or special characters
- **Evidence**:
  ```bash
  # modules/vm/main.tf:50 - unquoted $DISK_PARAM
  "--scsi0 $DISK_PARAM"
  ```
- **Fix**: Quote all variables in pvesh commands

### 4. **SSH Key Path Not Expanded in Terraform** (HIGH)
- **Location**: All modules using `${self.triggers.pm_ssh_key}`
- **Problem**: `~/.ssh/id_rsa` doesn't expand in Terraform provisioners
- **Impact**: SSH commands fail with "No such file or directory"
- **Evidence**: Variables default to `~/.ssh/id_rsa` but `~` doesn't expand in provisioners
- **Fix**: Expand `~` in setup.sh before passing to Terraform, or use absolute paths

### 5. **Missing Error Handling in pvesh Commands** (MEDIUM)
- **Location**: Most modules - pvesh commands don't check exit codes
- **Problem**: Failures are silent or produce cryptic errors
- **Impact**: Hard to debug why resources weren't created
- **Evidence**: 
  ```bash
  # modules/vm/main.tf:50 - no error check after pvesh
  ssh ... "pvesh create /nodes/..."
  ```
- **Fix**: Add explicit error checking and meaningful error messages

### 6. **Backup Job Cron Parsing Fragility** (MEDIUM)
- **Location**: `modules/backup_job/main.tf` lines 19-44
- **Problem**: Simple `awk` parsing assumes specific cron format
- **Impact**: Fails with non-standard cron expressions
- **Evidence**: Only handles `minute hour * * *` format
- **Fix**: Add validation and better parsing

### 7. **No Preflight Validation Before Terraform Apply** (MEDIUM)
- **Location**: `setup.sh` - preflight_checks() exists but may not catch all issues
- **Problem**: Missing checks for:
  - Actual node name matching (not just existence)
  - Storage availability on specific nodes
  - VMID conflicts across nodes
  - pvesh authentication/permissions
- **Impact**: Terraform fails mid-apply with unclear errors
- **Fix**: Enhance preflight_checks() with comprehensive validation

### 8. **Cluster Module Missing Node Parameter** (LOW)
- **Location**: `modules/cluster/main.tf` - cluster creation doesn't specify node
- **Problem**: `pvecm create` runs on SSH host, but which node?
- **Impact**: May create cluster on wrong node in multi-node setup
- **Fix**: Explicitly specify primary node

---

## What to Check First (10-Minute Checklist)

### Step 1: Verify SSH Access (2 min)
```bash
# Test SSH connectivity
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "echo 'SSH OK'"

# Test pvesh availability
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /version"
```

### Step 2: Verify Node Names Match (2 min)
```bash
# List actual nodes in Proxmox
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /nodes --output-format json | jq -r '.[].node'"

# Compare with your VM configs
grep -r "node.*=" /root/thinkdeploy-proxmox-platform/*.tfvars.json 2>/dev/null || echo "No tfvars found"
```

### Step 3: Verify Storage Exists (2 min)
```bash
# List storage on each node
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /storage --output-format json | jq -r '.[].storage'"

# Check specific storage
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /nodes/<node>/storage/<storage-name>"
```

### Step 4: Verify VMID Availability (2 min)
```bash
# List existing VMIDs
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /nodes/<node>/qemu --output-format json | jq -r '.[].vmid'"
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /nodes/<node>/lxc --output-format json | jq -r '.[].vmid'"
```

### Step 5: Test pvesh Command Manually (2 min)
```bash
# Try creating a test VM manually (will fail if VMID exists, that's OK)
ssh -i ~/.ssh/id_rsa root@<proxmox-host> \
  "pvesh create /nodes/<node>/qemu --vmid 999 --name test-vm --cores 1 --memory 512 --net0 model=virtio,bridge=vmbr0 --scsi0 local-lvm:5120"

# If successful, delete it
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh delete /nodes/<node>/qemu/999"
```

---

## Fixes (with patches)

### Fix 1: Networking Module - Replace localhost with actual node

**File**: `modules/networking/main.tf`

**Problem**: Hardcoded `localhost` in all pvesh commands

**Fix**:
```terraform
# Add node variable to networking module
# Then replace all instances of /nodes/localhost/network with /nodes/${var.node}/network
```

**Patch**:
```diff
--- a/modules/networking/main.tf
+++ b/modules/networking/main.tf
@@ -16,7 +16,7 @@ resource "null_resource" "bridge" {
   provisioner "local-exec" {
     command = <<-EOT
       # Create bridge
-      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
-        "pvesh create /nodes/localhost/network --iface ${self.triggers.bridge_name} --type bridge --bridge_ports ${self.triggers.iface} --stp ${self.triggers.stp} --mtu ${self.triggers.mtu}" || echo "Bridge may already exist"
+      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
+        "pvesh create /nodes/${self.triggers.node}/network --iface ${self.triggers.bridge_name} --type bridge --bridge_ports ${self.triggers.iface} --stp ${self.triggers.stp} --mtu ${self.triggers.mtu}" || echo "Bridge may already exist"
     EOT
   }
 }
```

**Note**: Need to add `node` to networking module variables and pass from main.tf

### Fix 2: Add Module Dependencies

**File**: `main.tf`

**Problem**: No ordering between modules

**Fix**:
```terraform
# Add depends_on to ensure proper ordering
module "vm" {
  for_each = var.vms
  # ... existing config ...
  depends_on = [
    module.cluster,
    module.storage,
    module.networking
  ]
}
```

**Patch**:
```diff
--- a/main.tf
+++ b/main.tf
@@ -21,6 +21,10 @@ module "vm" {
   pm_ssh_host             = var.pm_ssh_host
   pm_ssh_user             = var.pm_ssh_user
   pm_ssh_private_key_path = var.pm_ssh_private_key_path
+
+  depends_on = [
+    module.cluster,
+    module.storage
+  ]
 }
 
 # LXC modules
@@ -35,6 +39,10 @@ module "lxc" {
   pm_ssh_host             = var.pm_ssh_host
   pm_ssh_user             = var.pm_ssh_user
   pm_ssh_private_key_path = var.pm_ssh_private_key_path
+
+  depends_on = [
+    module.cluster,
+    module.storage
+  ]
 }
```

### Fix 3: Quote Variables in pvesh Commands

**File**: `modules/vm/main.tf`

**Problem**: Unquoted `$DISK_PARAM` and other variables

**Fix**:
```diff
--- a/modules/vm/main.tf
+++ b/modules/vm/main.tf
@@ -48,7 +48,7 @@
       
       echo "Creating VM ${self.triggers.vmid} on node ${self.triggers.node}..."
       ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
-        "pvesh create /nodes/${self.triggers.node}/qemu --vmid ${self.triggers.vmid} --name vm-${self.triggers.vmid} --cores ${self.triggers.cores} --memory ${self.triggers.memory} --net0 ${self.triggers.network} --scsi0 $DISK_PARAM"
+        "pvesh create /nodes/${self.triggers.node}/qemu --vmid ${self.triggers.vmid} --name vm-${self.triggers.vmid} --cores ${self.triggers.cores} --memory ${self.triggers.memory} --net0 '${self.triggers.network}' --scsi0 '$DISK_PARAM'"
       
       if [ $? -eq 0 ]; then
         echo "VM ${self.triggers.vmid} created successfully"
```

**Apply same fix to**:
- `modules/lxc/main.tf` line 37 (quote `$ROOTFS_PARAM`)
- `modules/backup_job/main.tf` line 48 (quote all variables)

### Fix 4: Expand SSH Key Path in setup.sh

**File**: `setup.sh`

**Problem**: `~/.ssh/id_rsa` doesn't expand in Terraform provisioners

**Fix**:
```diff
--- a/setup.sh
+++ b/setup.sh
@@ -130,6 +130,8 @@
     read -p "SSH private key path [~/.ssh/id_rsa]: " pm_ssh_key
     pm_ssh_key=${pm_ssh_key:-~/.ssh/id_rsa}
     pm_ssh_key="${pm_ssh_key/#\~/$HOME}"
+    # Expand to absolute path for Terraform
+    pm_ssh_key=$(readlink -f "$pm_ssh_key" 2>/dev/null || echo "$pm_ssh_key")
     [[ ! -f "$pm_ssh_key" ]] && error_exit "SSH key file not found: $pm_ssh_key"
     
     # Export variables for terraform
```

### Fix 5: Add Error Handling to pvesh Commands

**File**: `modules/vm/main.tf`

**Problem**: No error checking after pvesh commands

**Fix**:
```diff
--- a/modules/vm/main.tf
+++ b/modules/vm/main.tf
@@ -48,9 +48,15 @@
       
       echo "Creating VM ${self.triggers.vmid} on node ${self.triggers.node}..."
       ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
-        "pvesh create /nodes/${self.triggers.node}/qemu --vmid ${self.triggers.vmid} --name vm-${self.triggers.vmid} --cores ${self.triggers.cores} --memory ${self.triggers.memory} --net0 ${self.triggers.network} --scsi0 $DISK_PARAM"
+        "pvesh create /nodes/${self.triggers.node}/qemu --vmid ${self.triggers.vmid} --name vm-${self.triggers.vmid} --cores ${self.triggers.cores} --memory ${self.triggers.memory} --net0 '${self.triggers.network}' --scsi0 '$DISK_PARAM'" 2>&1
       
-      if [ $? -eq 0 ]; then
+      PVE_EXIT=$?
+      if [ $PVE_EXIT -eq 0 ]; then
         echo "VM ${self.triggers.vmid} created successfully"
       else
-        echo "ERROR: Failed to create VM ${self.triggers.vmid}"
+        echo "ERROR: Failed to create VM ${self.triggers.vmid} (exit code: $PVE_EXIT)"
+        echo "Check: node=${self.triggers.node}, vmid=${self.triggers.vmid}, storage=${self.triggers.storage}"
         exit 1
       fi
```

### Fix 6: Enhance Preflight Checks

**File**: `setup.sh`

**Problem**: Preflight checks don't validate node name matching

**Fix**: Add to `preflight_checks()` function around line 2000:
```bash
# Validate node names match exactly (case-sensitive)
log "Validating node name matching..."
ALL_NODES=$(echo "{$vms}{$lxcs}" | jq -r '.[] | .node' 2>/dev/null | sort -u || echo "")
PROXMOX_NODES=$(ssh -o StrictHostKeyChecking=no -i "${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}" \
  "${TF_VAR_pm_ssh_user:-root}@${TF_VAR_pm_ssh_host:-localhost}" \
  "pvesh get /nodes --output-format json 2>/dev/null" | jq -r '.[].node' 2>/dev/null || echo "")

for node in $ALL_NODES; do
  if ! echo "$PROXMOX_NODES" | grep -q "^${node}$"; then
    error_exit "Node '$node' not found in Proxmox. Available nodes: $PROXMOX_NODES"
  fi
done
```

### Fix 7: Fix Backup Job Cron Parsing

**File**: `modules/backup_job/main.tf`

**Problem**: Fragile cron parsing

**Fix**: Add validation:
```diff
--- a/modules/backup_job/main.tf
+++ b/modules/backup_job/main.tf
@@ -18,6 +18,12 @@
     command = <<-EOT
       # Parse cron schedule and create backup job
       CRON_SCHEDULE="${self.triggers.schedule}"
+      
+      # Validate cron format (basic check)
+      if ! echo "$CRON_SCHEDULE" | grep -qE '^[0-9*]+ [0-9*]+ [0-9*]+ [0-9*]+ [0-9*]+'; then
+        echo "ERROR: Invalid cron format: $CRON_SCHEDULE"
+        exit 1
+      fi
       
       # Extract time from cron (format: minute hour * * *)
       HOUR=$(echo $CRON_SCHEDULE | awk '{print $2}')
```

---

## Preflight Check Script

Create standalone preflight script: `preflight.sh`

```bash
#!/bin/bash
set -euo pipefail

# Source connection vars
source <(grep "^TF_VAR_" .env 2>/dev/null || true)

SSH_HOST="${TF_VAR_pm_ssh_host:-localhost}"
SSH_USER="${TF_VAR_pm_ssh_user:-root}"
SSH_KEY="${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"

echo "=== Preflight Checks ==="

# 1. Check binaries
for cmd in terraform jq ssh pvesh; do
  if ! command -v $cmd &>/dev/null; then
    echo "❌ Missing: $cmd"
    exit 1
  fi
  echo "✅ $cmd found"
done

# 2. Check SSH
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY" \
  "${SSH_USER}@${SSH_HOST}" "echo OK" &>/dev/null; then
  echo "❌ SSH connection failed"
  exit 1
fi
echo "✅ SSH connection OK"

# 3. Check pvesh
if ! ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" \
  "pvesh get /version" &>/dev/null; then
  echo "❌ pvesh not working"
  exit 1
fi
echo "✅ pvesh working"

# 4. List nodes
echo ""
echo "Available nodes:"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" \
  "pvesh get /nodes --output-format json" | jq -r '.[].node'

# 5. List storage
echo ""
echo "Available storage:"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" \
  "pvesh get /storage --output-format json" | jq -r '.[].storage'

echo ""
echo "✅ All preflight checks passed"
```

---

## Testing Checklist

After applying fixes:

1. **Test SSH key expansion**:
   ```bash
   ./setup.sh
   # Use ~/.ssh/id_rsa, verify it expands to absolute path in logs
   ```

2. **Test node name matching**:
   ```bash
   # Configure VM with node name that doesn't exist
   # Should fail in preflight with clear error
   ```

3. **Test module dependencies**:
   ```bash
   terraform plan -var-file=test.tfvars.json
   # Verify VM module shows depends_on in plan
   ```

4. **Test quoted variables**:
   ```bash
   # Create VM with network config containing spaces
   # Should work without breaking
   ```

5. **Test error handling**:
   ```bash
   # Try creating VM with invalid storage
   # Should show clear error message
   ```

---

## Summary

**Critical fixes (apply first)**:
1. Fix networking module localhost → node variable
2. Add module dependencies
3. Quote all pvesh variables
4. Expand SSH key path

**Important fixes (apply next)**:
5. Add error handling to pvesh commands
6. Enhance preflight checks
7. Fix backup job cron parsing

**Files to modify**:
- `modules/networking/main.tf` (4 instances)
- `modules/networking/variables.tf` (add node variable)
- `main.tf` (add depends_on)
- `modules/vm/main.tf` (quote variables, error handling)
- `modules/lxc/main.tf` (quote variables)
- `modules/backup_job/main.tf` (cron validation)
- `setup.sh` (SSH key expansion, preflight enhancement)
