# Terraform "No Changes" Issue - Root Cause & Fix

## Problem Summary

**Symptom**: `terraform apply` reports "No changes. Resources: 0 added, 0 changed, 0 destroyed" but VM is not created in Proxmox.

**Root Cause**: This is **expected Terraform behavior**, not a Proxmox issue.

## Why Terraform Says "No Changes"

Terraform's `null_resource` with `local-exec` provisioners only run when:

1. ✅ **Resource is newly created** (first time)
2. ✅ **Any value in `triggers` changes** (forces re-run)
3. ✅ **Resource is replaced/destroyed**

If:
- `null_resource.vm[0]` already exists in Terraform state
- `var.enabled == true` (resource is enabled)
- **All `triggers` values are identical** to previous apply

Then Terraform correctly determines there are **no changes** and does **NOT** execute the `local-exec` provisioner (the SSH/pvesh command).

**This is correct Terraform behavior** - Terraform assumes the resource was already created successfully in a previous run.

## Why Proxmox Never Receives the Create Command

The `local-exec` provisioner (which contains the `pvesh create` command) only runs when Terraform detects a change. If Terraform sees no changes, it never executes the provisioner, so Proxmox never receives the command.

## Secondary Issue: VM Existence Check

**Problem**: The script uses `qm status <vmid>` which:
- Only works on the local node
- Fails when SSH connects to a different node than where the VM should exist
- Not reliable in multi-node clusters

**Fix**: Use `pvesh get /nodes/<node>/qemu/<vmid>/status/current` which:
- Works across SSH connections
- Queries the correct node explicitly
- Returns JSON for reliable parsing

## Solution: Force Run Trigger (Option A - Recommended)

### Implementation

Add a `force_run` trigger that can be set to `timestamp()` to force re-execution:

**1. Add variable to VM module** (`modules/vm/variables.tf`):
```terraform
variable "force_run" {
  description = "Force re-run of VM creation (use timestamp() to force on each apply)"
  type        = string
  default     = ""
}
```

**2. Add to triggers** (`modules/vm/main.tf`):
```terraform
triggers = {
  # ... existing triggers ...
  force_run = var.force_run
}
```

**3. Add root variable** (`variables.tf`):
```terraform
variable "vm_force_run" {
  description = "Force re-run of VM creation (use timestamp() to force on each apply, or empty string to disable)"
  type        = string
  default     = ""
}
```

**4. Pass to module** (`main.tf`):
```terraform
module "vm" {
  # ... existing config ...
  force_run = var.vm_force_run
}
```

### Usage

**Option 1: Force on every apply** (for testing/debugging):
```bash
terraform apply -var="vm_force_run=$(date +%s)"
```

**Option 2: Set in tfvars** (for Deploy All):
```hcl
vm_force_run = timestamp()
```

**Option 3: Disable** (production - only create if triggers change):
```hcl
vm_force_run = ""
```

## Fix: VM Existence Check

**Before** (unreliable):
```bash
qm status ${self.triggers.vmid} >/dev/null 2>&1
```

**After** (reliable):
```bash
VM_EXISTS=$(ssh ... "pvesh get /nodes/${self.triggers.node}/qemu/${self.triggers.vmid}/status/current --output-format json 2>/dev/null" | jq -r '.status // empty' 2>/dev/null || echo "")
if [ -n "$VM_EXISTS" ] && [ "$VM_EXISTS" != "null" ]; then
  echo "VM already exists, skipping"
  exit 0
fi
```

## Code Diff Summary

### modules/vm/variables.tf
```diff
+variable "force_run" {
+  description = "Force re-run of VM creation (use timestamp() to force on each apply)"
+  type        = string
+  default     = ""
+}
```

### modules/vm/main.tf
```diff
  triggers = {
    # ... existing ...
+   force_run = var.force_run
  }

  provisioner "local-exec" {
    command = <<-EOT
-     ssh ... "qm status ${self.triggers.vmid} >/dev/null 2>&1"
+     VM_EXISTS=$(ssh ... "pvesh get /nodes/${self.triggers.node}/qemu/${self.triggers.vmid}/status/current --output-format json 2>/dev/null" | jq -r '.status // empty' 2>/dev/null || echo "")
+     if [ -n "$VM_EXISTS" ] && [ "$VM_EXISTS" != "null" ]; then
+       echo "VM already exists, skipping"
+       exit 0
+     fi
```

### variables.tf
```diff
+variable "vm_force_run" {
+  description = "Force re-run of VM creation"
+  type        = string
+  default     = ""
+}
```

### main.tf
```diff
  module "vm" {
    # ... existing ...
+   force_run = var.vm_force_run
  }
```

## Verification Steps

1. **Check state**:
   ```bash
   terraform state list | grep null_resource.vm
   # Should show: module.vm["vm-name"].null_resource.vm[0]
   ```

2. **Check plan**:
   ```bash
   terraform plan
   # Without force_run: "No changes"
   # With force_run=timestamp(): "null_resource.vm[0] will be replaced"
   ```

3. **Force run**:
   ```bash
   terraform apply -var="vm_force_run=$(date +%s)"
   # Should show: "null_resource.vm[0] must be replaced"
   ```

## Production Recommendation

**For production deployments**:

1. **Default**: `vm_force_run = ""` (empty) - only create when triggers change
2. **Deploy All**: Set `vm_force_run = timestamp()` in setup.sh when building tfvars
3. **Manual force**: Use `terraform apply -replace="module.vm[\"name\"].null_resource.vm[0]"` for specific VMs

**Why this approach**:
- ✅ Respects Terraform's idempotency model
- ✅ Allows intentional force-runs when needed
- ✅ Prevents accidental re-creation in production
- ✅ Works with Deploy All workflow

## Alternative: Manual Replace (Option B - Temporary)

If you need to force a single VM creation without modifying code:

```bash
terraform apply -replace="module.vm[\"vm-name\"].null_resource.vm[0]"
```

This forces Terraform to replace the resource, triggering the provisioner.

## Summary

- **"No changes" is correct** - Terraform sees no trigger changes
- **Proxmox never receives command** - because provisioner doesn't run
- **Solution**: Add `force_run` trigger for intentional re-runs
- **Fix**: Use `pvesh` instead of `qm status` for existence check
- **Production**: Use `force_run = timestamp()` only when needed (Deploy All)
