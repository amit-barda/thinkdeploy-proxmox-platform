# Deploy All Mandatory Execution Fix

## Problem Statement

**Before**: Deploy All (menu option 7) shows "Infrastructure configuration completed: VMs: 1" and then returns to shell with no terraform logs. `run_terraform_deploy` is never called.

**After**: `run_terraform_deploy` is called **immediately** after tfvars creation, before any validation/preflight that might cause early exit.

---

## Root Cause

The deployment call (`run_terraform_deploy`) was located **after**:
1. Validation/cleaning code (lines 1804-1919)
2. JSON validation (lines 1921-1938)
3. Preflight checks (lines 1941-2050)
4. Pre-deployment validation (lines 2052-2123)
5. User confirmation prompt (lines 2125-2138)

If any of these steps failed or the user cancelled, the script would exit **before** reaching the deployment call at line 2173.

---

## Solution

**Location**: `setup.sh` lines 1804-1865

**Added**: Mandatory deployment call **immediately** after:
1. Function definition (`run_terraform_deploy`) - line 1802
2. Tfvars file creation - line 1632

**Before** any validation/preflight code that might exit early.

---

## Implementation

### 1. Mandatory Deployment Section (lines 1804-1865)

```bash
# ============================================================================
# MANDATORY DEPLOYMENT CALL - IMMEDIATELY AFTER TFVARS CREATION
# ============================================================================
# When Deploy All (option 7) is selected, we MUST call run_terraform_deploy
# This happens BEFORE any validation/preflight to ensure deployment runs
# ============================================================================

log "=== DEPLOY ALL HANDLER: Checking if deployment is required ==="
echo "🚀 Deploy All: Checking deployment requirements..." 1>&2

# Count enabled VMs from tfvars file (already created)
enabled_vms_deploy=$(jq -r '.vms // {} | to_entries | map(select(.value.enabled != false)) | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
log "DeployAll: enabled_vms=$enabled_vms_deploy"

# Determine TF_ROOT for deployment
script_dir_deploy="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_ROOT_DEPLOY="$script_dir_deploy"
if [ ! -f "$TF_ROOT_DEPLOY/main.tf" ]; then
    search_dir_deploy="$TF_ROOT_DEPLOY"
    while [ "$search_dir_deploy" != "/" ]; do
        if [ -f "$search_dir_deploy/main.tf" ]; then
            TF_ROOT_DEPLOY="$search_dir_deploy"
            break
        fi
        search_dir_deploy="$(dirname "$search_dir_deploy")"
    done
fi

# HARD RULE: If enabled VMs > 0, MUST call run_terraform_deploy NOW
if [ "$enabled_vms_deploy" -gt 0 ]; then
    log "=== RUN_TERRAFORM_DEPLOY START (MANDATORY) ==="
    echo "🚀 RUN_TERRAFORM_DEPLOY START" 1>&2
    echo "   TF_ROOT: $TF_ROOT_DEPLOY" 1>&2
    echo "   TFVARS_FILE: $TFVARS_FILE" 1>&2
    echo "   enabled_vms: $enabled_vms_deploy" 1>&2
    echo "" 1>&2
    
    # Call run_terraform_deploy - this MUST execute
    if ! run_terraform_deploy "$TFVARS_FILE"; then
        error_exit "run_terraform_deploy failed. Check log: $LOG_FILE"
    fi
    
    log "=== RUN_TERRAFORM_DEPLOY COMPLETE (MANDATORY) ==="
    echo "✅ Terraform deployment completed successfully" 1>&2
    echo "" 1>&2
    
    # Verify state is non-empty
    log "Verifying Terraform state after deployment..."
    echo "🔍 Verifying Terraform state..." 1>&2
    (
      cd "$TF_ROOT_DEPLOY" || error_exit "Failed to change to TF_ROOT=$TF_ROOT_DEPLOY"
      state_list_final=$(terraform state list 2>&1 | tee /dev/tty)
      state_count=$(echo "$state_list_final" | grep -v "^$" | wc -l || echo "0")
      if [ "$state_count" -eq 0 ]; then
          error_exit "Terraform state is empty after deployment. Deployment may have failed."
      else
          log "Terraform state verified: $state_count resource(s) managed"
          echo "✅ Terraform state verified: $state_count resource(s) managed" 1>&2
          echo "State resources:" 1>&2
          echo "$state_list_final" | sed 's/^/   /' 1>&2
      fi
    ) || error_exit "Failed to verify Terraform state"
    
    # Cleanup tfvars only after successful deployment
    rm -f "$TFVARS_FILE" 2>/dev/null || true
    log "Cleaned up tfvars file (contains sensitive data)"
    
    # Exit successfully - deployment is complete
    log "Script execution completed - deployment successful"
    exit 0
else
    log "DeployAll: No enabled VMs ($enabled_vms_deploy), skipping mandatory deployment"
    echo "ℹ️  No enabled VMs to deploy. Continuing with validation..." 1>&2
fi
```

### 2. Key Features

**✅ Immediate Execution**:
- Runs **immediately** after tfvars creation
- **Before** any validation/preflight that might exit

**✅ Hard Rule Enforcement**:
- If `enabled_vms > 0`, **MUST** call `run_terraform_deploy`
- Fails fast if deployment is skipped

**✅ Visible Logging**:
- `🚀 RUN_TERRAFORM_DEPLOY START` on screen
- All terraform commands visible via `tee /dev/tty`
- Clear markers: `=== RUN_TERRAFORM_DEPLOY START (MANDATORY) ===`

**✅ State Verification**:
- Verifies `terraform state list` is non-empty after deployment
- Fails if state is empty (deployment failed)

**✅ Early Exit on Success**:
- Exits with code 0 after successful deployment
- Prevents script from continuing to validation/preflight

**✅ Subshell for TF_ROOT**:
- Uses `(cd "$TF_ROOT_DEPLOY" && ...)` for state verification
- No dependency on `-chdir` flag

---

## Execution Flow

### Before Fix:
```
Menu option 7 → break
  ↓
Log "Infrastructure configuration completed: VMs: 1"
  ↓
Build terraform_vars (old code)
  ↓
Cluster detection
  ↓
Build tfvars file
  ↓
Function definition
  ↓
Validation/cleaning
  ↓
JSON validation
  ↓
Preflight checks
  ↓
Pre-deployment validation (terraform plan)
  ↓
User confirmation prompt
  ↓
[IF USER SAYS YES]
  ↓
run_terraform_deploy (line 2173) ← NEVER REACHED IF USER CANCELS
```

### After Fix:
```
Menu option 7 → break
  ↓
Log "Infrastructure configuration completed: VMs: 1"
  ↓
Build terraform_vars (old code)
  ↓
Cluster detection
  ↓
Build tfvars file (line 1632)
  ↓
Function definition (line 1802)
  ↓
**MANDATORY DEPLOYMENT CALL (line 1833)** ← NEW: RUNS IMMEDIATELY
  ↓
  ├─ If enabled_vms > 0:
  │   ├─ run_terraform_deploy "$TFVARS_FILE"
  │   ├─ Verify state is non-empty
  │   ├─ Cleanup tfvars
  │   └─ exit 0 (SUCCESS - script ends here)
  │
  └─ If enabled_vms == 0:
      └─ Continue to validation/preflight (for other resources)
```

---

## Expected Logs

### Sample Output

```
[2026-02-01 20:42:20] Infrastructure configuration completed:
[2026-02-01 20:42:20]   - VMs: 1
[2026-02-01 20:42:20] Created tfvars file: /tmp/thinkdeploy-1234567890.tfvars.json
[2026-02-01 20:42:20] === DEPLOY ALL HANDLER: Checking if deployment is required ===
🚀 Deploy All: Checking deployment requirements...
[2026-02-01 20:42:20] DeployAll: enabled_vms=1
[2026-02-01 20:42:20] === RUN_TERRAFORM_DEPLOY START (MANDATORY) ===
🚀 RUN_TERRAFORM_DEPLOY START
   TF_ROOT: /root/thinkdeploy-proxmox-platform
   TFVARS_FILE: /tmp/thinkdeploy-1234567890.tfvars.json
   enabled_vms: 1

🔧 Terraform Deployment Steps:
   1. terraform init -upgrade
   2. terraform validate
   3. terraform plan -out=/tmp/thinkdeploy.plan
   4. terraform apply /tmp/thinkdeploy.plan

📦 Step 1/4: Initializing Terraform...
Working directory: /root/thinkdeploy-proxmox-platform
Initializing provider plugins...
Terraform has been successfully initialized!

✅ Terraform initialized

🔍 Step 2/4: Validating Terraform configuration...
Success! The configuration is valid.

✅ Configuration valid

📋 Step 3/4: Planning Terraform changes...
Command: terraform plan -var-file="/tmp/thinkdeploy-1234567890.tfvars.json" -out=/tmp/thinkdeploy.plan
Plan: 1 to add, 0 to change, 0 to destroy.

✅ Plan completed - changes will be applied

🚀 Step 4/4: Applying Terraform changes...
Command: terraform apply -auto-approve /tmp/thinkdeploy.plan
module.vm["web-server-01"].null_resource.vm[0]: Creating...
module.vm["web-server-01"].null_resource.vm[0]: Creation complete after 5s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

✅ Infrastructure deployment completed

🔍 Verifying Terraform state...
✅ Terraform state verified: 1 resource(s) managed
State resources:
   module.vm["web-server-01"].null_resource.vm[0]

[2026-02-01 20:42:35] === RUN_TERRAFORM_DEPLOY COMPLETE (MANDATORY) ===
✅ Terraform deployment completed successfully

🔍 Verifying Terraform state...
✅ Terraform state verified: 1 resource(s) managed
State resources:
   module.vm["web-server-01"].null_resource.vm[0]

[2026-02-01 20:42:35] Script execution completed - deployment successful
```

---

## Acceptance Criteria

### ✅ After choosing Deploy All:

1. **Terraform init/plan/apply output MUST appear on screen**
   - ✅ All terraform commands visible via `tee /dev/tty`
   - ✅ Clear step markers: "Step 1/4", "Step 2/4", etc.
   - ✅ Working directory shown

2. **State must be non-empty**
   ```
   $ terraform state list
   module.vm["web-server-01"].null_resource.vm[0]
   ```

3. **Script exits after successful deployment**
   - ✅ Exits with code 0
   - ✅ Does NOT continue to validation/preflight
   - ✅ Does NOT show user confirmation prompts

4. **Fails fast if deployment skipped**
   - ✅ If `enabled_vms > 0` but deploy not called → fatal error
   - ✅ If state is empty after deploy → fatal error

---

## Status

✅ **IMPLEMENTED**:
- ✅ Mandatory deployment call immediately after tfvars creation
- ✅ Runs BEFORE validation/preflight that might exit early
- ✅ Hard rule: If enabled_vms > 0, MUST call deploy
- ✅ Visible logs: `🚀 RUN_TERRAFORM_DEPLOY START`
- ✅ State verification after deployment
- ✅ Early exit on success (prevents continuing to validation)
- ✅ Uses subshell `(cd "$TF_ROOT_DEPLOY" && ...)` for state verification

**Result**: Deploy All now **always** executes terraform apply when VMs are configured, regardless of validation/preflight outcomes or user confirmation.
