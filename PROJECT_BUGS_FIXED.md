# Project Bugs Fixed

## Summary
Fixed critical bugs in the actual project code that would prevent proper deployment and cause failures.

## Bugs Fixed

### 1. LXC Module - Missing Existence Check
**File**: `modules/lxc/main.tf`
**Issue**: LXC containers were being created without checking if they already exist, causing errors on re-runs.
**Fix**: Added existence check using `pvesh get /nodes/<node>/lxc/<vmid>/status/current` before creation, matching the VM module pattern.

### 2. Backup Job Module - Incorrect vmid Parameter Format
**File**: `modules/backup_job/main.tf`
**Issue**: The `--vmid` parameter was receiving a comma-separated string, but pvesh expects space-separated values.
**Fix**: Convert comma-separated VM list to space-separated format before passing to pvesh.

### 3. Snapshot Module - Missing Error Handling
**File**: `modules/snapshot/main.tf`
**Issue**: No exit code checking after pvesh create, and unquoted description parameter could break with spaces.
**Fix**: 
- Added proper error handling with exit code checking
- Fixed description parameter quoting
- Added null check for description

### 4. Storage Module - Missing Parameter Quoting
**File**: `modules/storage/main.tf`
**Issue**: Storage parameters (name, server, export, content) were not quoted, causing failures with special characters or spaces.
**Fix**: Added proper quoting around all pvesh parameters.

### 5. Cluster HA Groups Module - Incorrect Nodes Format
**File**: `modules/cluster/main.tf`
**Issue**: HA group nodes parameter was passed as comma-separated string, but pvesh expects space-separated.
**Fix**: Convert comma-separated nodes to space-separated format and add proper error handling.

### 6. Security Module - Unreliable Token Existence Check
**File**: `modules/security/main.tf`
**Issue**: Token existence check used `wc -l` which is unreliable. Missing error handling and proper output redirection.
**Fix**:
- Replaced `wc -l` with proper JSON parsing using `jq`
- Added proper error handling with exit codes
- Added 2>&1 output redirection
- Fixed parameter quoting

## Impact

These fixes ensure:
- **Idempotency**: Resources check for existence before creation
- **Error Handling**: Proper exit codes and error messages
- **Parameter Formatting**: Correct pvesh command syntax
- **Reliability**: Proper quoting prevents failures with special characters

## Validation

All changes validated with:
- `terraform validate` - ✅ Passes
- `terraform fmt -check` - ✅ Passes

## Files Modified

1. `modules/lxc/main.tf` - Added existence check
2. `modules/backup_job/main.tf` - Fixed vmid parameter format
3. `modules/snapshot/main.tf` - Added error handling and proper quoting
4. `modules/storage/main.tf` - Added parameter quoting
5. `modules/cluster/main.tf` - Fixed nodes format and error handling
6. `modules/security/main.tf` - Improved token check and error handling
