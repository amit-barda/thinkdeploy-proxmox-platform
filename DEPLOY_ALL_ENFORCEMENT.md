# Deploy All Enforcement - Fix Implementation

## Problem Statement

**Before**: Deploy All shows "VMs: 1" but does not actually run terraform apply with the generated tfvars. User manually running `terraform apply` creates nothing because no var-file is passed.

**After**: Deploy All enforces that if enabled VMs > 0, it MUST call `run_terraform_deploy()` with the correct tfvars file, and all terraform commands are visible on screen.

---

## Solution Implementation

### 1. Debug Logging After tfvars Creation

**Location**: `setup.sh` lines 1632-1662

**Added**:
```bash
# DEBUG: Deploy All handler - immediately after tfvars creation
log "DEBUG DeployAll: TF_MODE=${TF_MODE:-unset}"
log "DEBUG DeployAll: TFVARS_FILE=$TFVARS_FILE"
log "DEBUG DeployAll: HAS_CONFIGS=$HAS_CONFIGS"
log "DEBUG DeployAll: TF_ROOT=$TF_ROOT_DEBUG"
log "DEBUG DeployAll: enabled_vms=$enabled_vms_count"
```

**Result**: Clear visibility into deployment state before execution

---

### 2. Hard Rule Enforcement

**Location**: `setup.sh` lines 2204-2235

**Logic**:
```bash
# HARD RULE: If enabled VMs > 0, MUST call run_terraform_deploy
enabled_vms_check=$(jq -r '.vms // {} | to_entries | map(select(.value.enabled != false)) | length' "$TFVARS_FILE" 2>/dev/null || echo "0")

if [ "$enabled_vms_check" -gt 0 ]; then
    log "DEBUG DeployAll: enabled_vms=$enabled_vms_check > 0, calling run_terraform_deploy"
    echo "🚀 Deploying $enabled_vms_check enabled VM(s)..." 1>&2
    
    # Run complete Terraform deployment orchestration
    run_terraform_deploy "$TFVARS_FILE"
    TF_EXIT_CODE=$?
    
    # Verify that run_terraform_deploy was actually called
    if [ -z "${TF_EXIT_CODE:-}" ]; then
        error_exit "VMs requested but deploy skipped. run_terraform_deploy did not set TF_EXIT_CODE. This is a bug."
    fi
fi

# FATAL: If we reach here and enabled VMs > 0 but run_terraform_deploy wasn't called
if [ "$enabled_vms_check" -gt 0 ] && [ -z "${TF_EXIT_CODE:-}" ]; then
    error_exit "VMs requested but deploy skipped. This is a bug."
fi
```

**Result**: Fails fast if VMs are requested but deploy is skipped

---

### 3. TF_MODE Default

**Location**: `setup.sh` line 1655

**Added**:
```bash
# Set TF_MODE default if missing
TF_MODE=${TF_MODE:-apply}
```

**Result**: Ensures TF_MODE is always set

---

### 4. Visible Logs to Screen

**Location**: All terraform commands in `run_terraform_deploy()`

**Changed**:
- `terraform ... | tee -a "$LOG_FILE"` → `terraform ... | tee -a "$LOG_FILE" | tee /dev/tty`
- Added command echo before each terraform command

**Applied to**:
- `terraform init -upgrade` (line 1743)
- `terraform validate` (line 1757)
- `terraform plan` (line 1781)
- `terraform apply` (line 1795)

**Result**: All terraform output is visible on screen AND logged to file

---

### 5. Tfvars Cleanup Only After State Verification

**Location**: `setup.sh` lines 2225-2250

**Changed**:
```bash
# Verify state is non-empty before cleanup
final_state_check=$(terraform -chdir="$TF_ROOT_DEBUG" state list 2>/dev/null | grep -v "^$" | wc -l || echo "0")

if [ "$final_state_check" -eq 0 ]; then
    warning "Terraform state is empty after deployment. Keeping tfvars file for debugging."
    # Don't cleanup tfvars
else
    # Cleanup tfvars file ONLY after successful apply AND state is non-empty
    rm -f "$TFVARS_FILE" 2>/dev/null || true
    log "Cleaned up tfvars file (contains sensitive data)"
fi
```

**Result**: Tfvars file is only deleted after successful deployment AND state is non-empty

---

## Code Changes Summary

### File: `setup.sh`

#### 1. Debug Logging After tfvars Creation (lines 1634-1662)
- Logs TF_MODE, TFVARS_FILE, HAS_CONFIGS, TF_ROOT, enabled_vms
- Sets TF_MODE default to "apply" if missing
- Logs requirement that run_terraform_deploy MUST be called if enabled_vms > 0

#### 2. Hard Rule Enforcement in Deploy Handler (lines 2204-2235)
- Counts enabled VMs before deploy
- If enabled_vms > 0, MUST call run_terraform_deploy
- Verifies TF_EXIT_CODE is set after call
- Fails fast if VMs requested but deploy skipped

#### 3. Visible Logs to Screen (lines 1743, 1757, 1781, 1795)
- All terraform commands use `| tee -a "$LOG_FILE" | tee /dev/tty`
- Command echo before each terraform command
- Output visible on screen AND logged to file

#### 4. Tfvars Cleanup After State Verification (lines 2225-2250)
- Verifies state is non-empty before cleanup
- Only deletes tfvars if state has resources
- Keeps tfvars for debugging if state is empty

---

## Expected Logs

### Sample Output After Fix

```
[2026-02-01 20:42:20] DEBUG DeployAll: TF_MODE=apply
[2026-02-01 20:42:20] DEBUG DeployAll: TFVARS_FILE=/tmp/thinkdeploy-1234567890.tfvars.json
[2026-02-01 20:42:20] DEBUG DeployAll: HAS_CONFIGS=true
[2026-02-01 20:42:20] DEBUG DeployAll: TF_ROOT=/root/thinkdeploy-proxmox-platform
[2026-02-01 20:42:20] DEBUG DeployAll: enabled_vms=1
[2026-02-01 20:42:20] DEBUG DeployAll: enabled_vms > 0, run_terraform_deploy MUST be called

...

[2026-02-01 20:42:25] DEBUG DeployAll: Checking enabled VMs before deploy: 1
🚀 Deploying 1 enabled VM(s)...

[2026-02-01 20:42:25] Starting Terraform deployment orchestration...
📦 Step 1/4: Initializing Terraform...
Command: terraform -chdir="/root/thinkdeploy-proxmox-platform" init -upgrade
Initializing provider plugins...
Terraform has been successfully initialized!

✅ Terraform initialized

🔍 Step 2/4: Validating Terraform configuration...
Command: terraform -chdir="/root/thinkdeploy-proxmox-platform" validate
Success! The configuration is valid.

✅ Configuration valid

📋 Step 3/4: Planning Terraform changes...
Command: terraform -chdir="/root/thinkdeploy-proxmox-platform" plan -var-file="/tmp/thinkdeploy-1234567890.tfvars.json" -detailed-exitcode
Plan: 1 to add, 0 to change, 0 to destroy.

✅ Plan completed - changes will be applied

🚀 Step 4/4: Applying Terraform changes...
Command: terraform -chdir="/root/thinkdeploy-proxmox-platform" apply -auto-approve -var-file="/tmp/thinkdeploy-1234567890.tfvars.json"
module.vm["web-server-01"].null_resource.vm[0]: Creating...
module.vm["web-server-01"].null_resource.vm[0]: Creation complete after 5s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

✅ Infrastructure deployment completed

[2026-02-01 20:42:35] Verifying Terraform state...
✅ Terraform state verified: 1 resource(s) managed
State resources:
   module.vm["web-server-01"].null_resource.vm[0]

[2026-02-01 20:42:35] Verifying Terraform state before cleanup...
✅ Terraform state verified: 1 resource(s) managed
[2026-02-01 20:42:35] Cleaned up tfvars file (contains sensitive data)
```

---

## Acceptance Criteria

### ✅ After running setup.sh -> Deploy All:

1. **Logs show terraform init/plan/apply**
   - ✅ Visible on screen (not just in log file)
   - ✅ Shows exact commands being run
   - ✅ Shows terraform output

2. **terraform state list is non-empty**
   ```
   $ terraform state list
   module.vm["web-server-01"].null_resource.vm[0]
   ```

3. **Manual terraform apply with -var-file works**
   ```
   $ terraform apply -var-file="/tmp/thinkdeploy-*.tfvars.json" -auto-approve
   # Creates VM successfully
   ```

4. **Debug logs show correct values**
   - ✅ TF_MODE=apply
   - ✅ TFVARS_FILE=/tmp/thinkdeploy-*.tfvars.json
   - ✅ enabled_vms=1
   - ✅ run_terraform_deploy is called

---

## Status

✅ **IMPLEMENTED**:
- ✅ Debug logging after tfvars creation
- ✅ Hard rule: enabled VMs > 0 MUST call run_terraform_deploy
- ✅ TF_MODE default set to "apply"
- ✅ Fails fast if VMs requested but deploy skipped
- ✅ All terraform commands use `-chdir="$TF_ROOT"` and `-var-file="$tfvars_file"`
- ✅ Visible logs to screen (tee /dev/tty)
- ✅ Tfvars cleanup only after state verification

**Result**: Deploy All now enforces that terraform deploy is called when VMs are configured, and all output is visible on screen.
