# VM Creation Fix - Minimal Code Diff

## Short Explanation

**Why Terraform says "No changes"**: `null_resource` with `local-exec` only runs when triggers change. If the resource exists in state and all triggers are identical, Terraform correctly reports "No changes" and **never executes the provisioner** (the `pvesh create` command).

**Why Proxmox never receives the command**: The `local-exec` provisioner doesn't run, so the SSH/pvesh command is never executed.

**This is expected Terraform behavior** - not a Proxmox issue.

## Minimal Code Diff

### 1. modules/vm/variables.tf
```diff
+variable "force_run" {
+  description = "Force re-run of VM creation (use timestamp() to force on each apply)"
+  type        = string
+  default     = ""
+}
```

### 2. modules/vm/main.tf
```diff
  triggers = {
    node        = var.node
    vmid        = var.vmid
    cores       = var.cores
    memory      = var.memory
    disk        = var.disk
    storage     = var.storage
    network     = var.network
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
+   force_run   = var.force_run
  }

  provisioner "local-exec" {
    command = <<-EOT
-     # Use exit-code based check: qm status returns 0 if VM exists, non-zero if not
-     ssh ... "qm status ${self.triggers.vmid} >/dev/null 2>&1"
-     if [ $? -eq 0 ]; then
+     # Use pvesh to query VM status on the specific node (works across SSH connections)
+     VM_EXISTS=$(ssh ... "pvesh get /nodes/${self.triggers.node}/qemu/${self.triggers.vmid}/status/current --output-format json 2>/dev/null" | jq -r '.status // empty' 2>/dev/null || echo "")
+     if [ -n "$VM_EXISTS" ] && [ "$VM_EXISTS" != "null" ]; then
-       echo "VM ${self.triggers.vmid} already exists on node ${self.triggers.node}, skipping creation"
+       echo "VM ${self.triggers.vmid} already exists on node ${self.triggers.node} (status: $VM_EXISTS), skipping creation"
        exit 0
       fi
```

### 3. variables.tf (root)
```diff
+variable "vm_force_run" {
+  description = "Force re-run of VM creation (use timestamp() to force on each apply, or empty string to disable)"
+  type        = string
+  default     = ""
+}
```

### 4. main.tf
```diff
  module "vm" {
    ...
    pm_ssh_host             = var.pm_ssh_host
    pm_ssh_user             = var.pm_ssh_user
    pm_ssh_private_key_path = var.pm_ssh_private_key_path
+   force_run               = var.vm_force_run
    ...
  }
```

### 5. setup.sh (build_tfvars_file function)
```diff
    # Add cluster config
    if [ -n "$cluster_configs" ] && [ -n "${CLUSTER_JSON:-}" ]; then
-       TFVARS_JSON="$TFVARS_JSON\"cluster_config\":$CLUSTER_JSON"
+       TFVARS_JSON="$TFVARS_JSON\"cluster_config\":$CLUSTER_JSON,"
    else
-       TFVARS_JSON="$TFVARS_JSON\"cluster_config\":{}"
+       TFVARS_JSON="$TFVARS_JSON\"cluster_config\":{},"
    fi
+   
+   # Add vm_force_run (use timestamp to force VM creation on Deploy All)
+   VM_FORCE_RUN=$(date +%s)
+   TFVARS_JSON="$TFVARS_JSON\"vm_force_run\":\"$VM_FORCE_RUN\""
    
    TFVARS_JSON="$TFVARS_JSON}"
```

## How It Works

1. **Default behavior** (`vm_force_run = ""`): Only creates VM when triggers change (normal Terraform behavior)
2. **Deploy All** (`vm_force_run = timestamp()`): Forces trigger change on every apply, ensuring provisioner runs
3. **VM existence check**: Uses `pvesh` to query specific node, works across SSH connections

## Verification

```bash
# Check state
terraform state list | grep null_resource.vm
# Output: module.vm["vm-name"].null_resource.vm[0]

# Plan without force_run (if resource exists)
terraform plan
# Output: "No changes"

# Plan with force_run (Deploy All sets this automatically)
terraform plan
# Output: "null_resource.vm[0] must be replaced" (triggers changed)
```

## Production Recommendation

✅ **Use `vm_force_run = timestamp()` in Deploy All** (already implemented in setup.sh)
- Ensures VMs are created/re-created when Deploy All runs
- Safe: VM existence check prevents duplicates
- Works with multi-node clusters

✅ **For manual applies**: Use `terraform apply -replace="module.vm[\"name\"].null_resource.vm[0]"` if needed

✅ **For production stability**: Can set `vm_force_run = ""` to disable forced re-runs (only create when triggers change)

## Summary

- ✅ Fixed: Added `force_run` trigger to force provisioner execution
- ✅ Fixed: Replaced `qm status` with `pvesh get /nodes/<node>/qemu/<vmid>/status/current`
- ✅ Integrated: setup.sh automatically sets `vm_force_run = timestamp()` for Deploy All
- ✅ Production-safe: VM existence check prevents duplicate creation
