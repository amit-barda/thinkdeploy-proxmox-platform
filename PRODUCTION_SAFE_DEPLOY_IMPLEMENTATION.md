# Production-Safe Terraform Deploy Flow Implementation

## Summary

Implemented a built-in, production-safe Terraform deploy flow inside `setup.sh` that prevents accidental resource destruction and ensures consistent tfvars file usage.

## Changes Implemented

### A) Persistent tfvars Location

**Before**: Tfvars written to `/tmp/thinkdeploy-$(date +%s).tfvars.json` (temporary, lost on reboot)

**After**: Tfvars written to `./generated/thinkdeploy.auto.tfvars.json` (persistent, inside repo)

**Implementation**:
- Created `./generated/` directory automatically
- Changed `TFVARS_FILE` location to `$TF_ROOT/generated/thinkdeploy.auto.tfvars.json`
- Added pointer file `./.thinkdeploy_last_tfvars` containing the path
- Set secure permissions (0600) on tfvars file (contains secrets)

**Location**: Lines 1578-1606 in `setup.sh`

### B) Built-in Terraform Orchestration

**Enhancement**: `run_terraform_deploy()` now always uses `-var-file` with the persistent path

**Implementation**:
- `run_terraform_deploy()` already used `-var-file`, now uses persistent path
- After successful apply, tfvars file is kept (not deleted) with secure permissions
- Added warning about sensitive data in tfvars file

**Location**: Lines 1710-1950 in `setup.sh`

### C) Safety Guard Against Accidental Destroy

**New Feature**: Prevents accidental destruction when:
1. Terraform state contains `module.vm` resources
2. Tfvars file has empty `vms: {}`
3. User hasn't explicitly set `THINKDEPLOY_ALLOW_DESTROY=true`

**Implementation**:
- Added safety checks in `run_terraform_deploy()` before plan/apply
- Checks if state has VMs but tfvars doesn't
- Requires `THINKDEPLOY_ALLOW_DESTROY=true` environment variable to proceed with destroy
- Validates Deploy All selection matches tfvars content

**Location**: Lines 1800-1850 in `setup.sh`

**Error Message Example**:
```
SAFETY GUARD: Terraform state contains module.vm resources, but tfvars file has empty vms: {}.
  This would destroy existing VMs!
  Tfvars file: ./generated/thinkdeploy.auto.tfvars.json
  If you intend to destroy resources, set: THINKDEPLOY_ALLOW_DESTROY=true
  Otherwise, ensure your tfvars file includes the VMs you want to keep.
```

### D) Proxmox Connection Validation

**New Feature**: Validates Proxmox connection settings before deployment

**Implementation**:
- New function `validate_proxmox_connection()` (lines 157-200)
- Validates SSH key exists and is accessible
- **Localhost Check**: If `pm_ssh_host=localhost`, validates:
  - `/etc/pve` directory exists (Proxmox indicator), OR
  - `pvesh` command works locally
  - Aborts if not running on Proxmox host
- Tests SSH connectivity before proceeding
- Called automatically when Proxmox connection variables are set

**Location**: Lines 157-200, 986 in `setup.sh`

**Error Message Example**:
```
pm_ssh_host is 'localhost' but this doesn't appear to be a Proxmox host:
  - /etc/pve directory not found
  - pvesh command not found
  Please set pm_ssh_host to the actual Proxmox node hostname/IP
```

### E) UX / Logging Improvements

**Enhancements**:
1. **Persistent tfvars path printed** at end of script
2. **Rerun commands** displayed clearly:
   ```
   terraform plan -var-file="./generated/thinkdeploy.auto.tfvars.json"
   terraform apply -var-file="./generated/thinkdeploy.auto.tfvars.json" -auto-approve
   ```
3. **Pointer file location** shown: `./.thinkdeploy_last_tfvars`
4. **Deployment summary** section at end with all paths and commands
5. **All paths logged** to `$LOG_FILE` for audit trail

**Location**: Lines 2450-2493 in `setup.sh`

## File Structure After Changes

```
thinkdeploy-proxmox-platform/
├── setup.sh
├── generated/
│   └── thinkdeploy.auto.tfvars.json  (0600 permissions, contains secrets)
├── .thinkdeploy_last_tfvars          (pointer to latest tfvars)
└── ...
```

## Usage

### Normal Deployment Flow

1. Run `./setup.sh`
2. Configure resources (VMs, storage, etc.)
3. Select "7. Deploy All"
4. Script automatically:
   - Validates Proxmox connection
   - Creates persistent tfvars in `./generated/`
   - Runs safety checks
   - Executes `terraform plan` and `apply` with `-var-file`
   - Keeps tfvars file with secure permissions

### Manual Terraform Commands

After deployment, use the persistent tfvars file:

```bash
# Plan changes
terraform plan -var-file="./generated/thinkdeploy.auto.tfvars.json"

# Apply changes
terraform apply -var-file="./generated/thinkdeploy.auto.tfvars.json" -auto-approve
```

### Intentional Resource Destruction

If you need to destroy resources (e.g., remove all VMs):

```bash
# 1. Edit tfvars to remove VMs (or set vms: {})
# 2. Set environment variable
export THINKDEPLOY_ALLOW_DESTROY=true

# 3. Run setup.sh or terraform apply
./setup.sh  # Select Deploy All
# OR
terraform apply -var-file="./generated/thinkdeploy.auto.tfvars.json" -auto-approve
```

## Safety Features

1. **Prevents accidental destroy**: Checks state vs tfvars before apply
2. **Requires explicit flag**: `THINKDEPLOY_ALLOW_DESTROY=true` for destructive operations
3. **Validates localhost**: Ensures user is actually on Proxmox host if using localhost
4. **Secure file permissions**: Tfvars file set to 0600 (read/write owner only)
5. **Persistent location**: Tfvars always in same location, not lost on reboot

## Backward Compatibility

- Existing workflows continue to work
- Menu system unchanged
- Deploy All flow enhanced but compatible
- No breaking changes to existing functionality

## Testing Checklist

- [x] Syntax validation (`bash -n setup.sh`)
- [x] Persistent tfvars location created
- [x] Pointer file written
- [x] Safety guard prevents accidental destroy
- [x] Proxmox connection validation works
- [x] UX improvements display correctly
- [x] File permissions set correctly (0600)

## Notes

- Tfvars file is **kept** after deployment (not deleted) for reruns
- Tfvars file contains **sensitive data** (SSH keys, passwords) - keep secure
- `generated/` directory should be added to `.gitignore` if using git
- Pointer file `.thinkdeploy_last_tfvars` can be committed (just contains path)
