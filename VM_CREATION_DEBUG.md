# VM Creation Debug - Root Cause Analysis

## Problem

**Symptom**: 
- setup.sh reports "VMs: 10"
- terraform apply completes without creating VMs
- No VM appears in Proxmox
- terraform plan shows "No changes"

**Evidence**:
- tfvars file contains: `{"vms": {"web-server-01": {...}}}`
- Terraform plan with test file shows: `module.vm["test-vm"].null_resource.vm[0] will be created`
- This proves Terraform CAN create VMs when tfvars is correct

---

## Root Cause Analysis

### 1. VM Data Flow

**Step 1: Collection** (setup.sh line 430)
```bash
vm_config="\"$vm_id\":{\"node\":\"$node\",\"vmid\":$vmid,...}"
echo "$vm_config"
```

**Step 2: Storage** (setup.sh line 990-1009)
```bash
result=$(configure_compute)
vms="$vms,$result"  # Appended as comma-separated string
```

**Step 3: Cleaning/Validation** (setup.sh lines 1623-1735)
```bash
temp_json="{${vms}}"  # Wrap in braces
# Parse with jq, separate VMs from LXCs
vms="$cleaned_vms"  # Reassign cleaned VMs
```

**Step 4: tfvars Building** (setup.sh line 1536)
```bash
TFVARS_JSON="$TFVARS_JSON\"vms\":{$vms},"
```

**Step 5: Terraform** (main.tf line 23)
```hcl
module "vm" {
  for_each = var.vms  # Iterates over map
  ...
}
```

### 2. Issues Found

#### Issue 1: Incorrect VM Count Logging

**Line 1074**:
```bash
[ -n "$vms" ] && log "  - VMs: $(echo "$vms" | tr ',' '\n' | wc -l)"
```

**Problem**: Counts commas, not actual VMs
- If `$vms = "vm1":{...},"vm2":{...},"vm3":{...}`
- `tr ',' '\n'` splits on ALL commas (including inside JSON)
- Result: Wrong count (e.g., 10 instead of 3)

**Fix**: Count actual VM keys from JSON
```bash
[ -n "$vms" ] && log "  - VMs: $(echo "{${vms}}" | jq 'keys | length' 2>/dev/null || echo "0")"
```

#### Issue 2: Terraform Syntax Error (FIXED)

**modules/cluster/main.tf line 25**:
```bash
echo "Cluster already exists in Proxmox: ${EXISTING_NAME:-unknown}"
```

**Problem**: Terraform interprets `${}` as interpolation
**Fix**: Use bash if statement instead

#### Issue 3: Potential JSON Structure Issue

The `$vms` variable is a comma-separated string like:
```
"vm1":{...},"vm2":{...},"vm3":{...}
```

When wrapped in `{$vms}`, it becomes:
```json
{"vm1":{...},"vm2":{...},"vm3":{...}}
```

This should be valid JSON, but if there's a trailing comma or malformed entry, it could break.

---

## Verification

### Test 1: Terraform Plan with Valid tfvars

**Input**: `/tmp/test_vm_tfvars.json`
```json
{
  "vms": {
    "test-vm": {
      "node": "local",
      "vmid": 999,
      "cores": 2,
      "memory": 2048,
      "disk": "50G",
      "storage": "local-lvm",
      "network": "model=virtio,bridge=vmbr0",
      "enabled": true
    }
  }
}
```

**Result**:
```
module.vm["test-vm"].null_resource.vm[0] will be created
Plan: 1 to add, 0 to change, 0 to destroy.
```

**Conclusion**: ✅ Terraform CAN create VMs when tfvars is correct

### Test 2: Check Actual tfvars File

**Command**:
```bash
find /tmp -name "thinkdeploy-*.tfvars.json" | xargs cat | jq '.vms | keys | length'
```

**Result**: `1` (only 1 VM in file, not 10)

**Conclusion**: ❌ tfvars file has fewer VMs than logged

---

## Root Cause

**Most Likely**: VMs are being lost during the cleaning/validation process (lines 1623-1735), OR the `$vms` variable is being overwritten/cleared somewhere.

**Secondary Issue**: VM count logging is wrong (counts commas, not VMs).

---

## Fixes Required

1. ✅ Fix Terraform syntax error in cluster module (DONE)
2. Fix VM count logging to use jq
3. Add validation to ensure VMs in tfvars match configured VMs
4. Add debug logging to track VMs through cleaning process
