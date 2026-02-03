# Test Fixes Applied

## Issues Fixed

### 1. BATS Test Helper Path
**Problem**: Tests in `tests/bash/` couldn't find `test_helper.bash` (was in parent directory)

**Fix**: Updated all bats files to use `load '../test_helper.bash'` instead of `load 'test_helper.bash'`

**Files Fixed**:
- `tests/bash/json_build_test.bats`
- `tests/bash/deploy_all_test.bats`
- `tests/bash/preflight_test.bats`

### 2. Test Helper Fixtures Path
**Problem**: `TEST_FIXTURES_DIR` path was incorrect for tests in subdirectories

**Fix**: Updated `test_helper.bash` to check for fixtures in parent directory first

**File Fixed**:
- `tests/test_helper.bash`

### 3. BATS Assertion Usage
**Problem**: Tests were using direct conditionals `[ ... ]` which don't work with `assert_success`

**Fix**: Wrapped all conditionals in `run bash -c "..."` to properly capture exit codes

**Files Fixed**:
- `tests/bash/deploy_all_test.bats` (7 tests)
- `tests/bash/preflight_test.bats` (8 tests)

### 4. JSON Test jq Path
**Problem**: jq path `.vms.test-vm.vmid` failed because of key quoting

**Fix**: Changed to `.vms.\"test-vm\".vmid` and added `has()` check first

**File Fixed**:
- `tests/bash/json_build_test.bats`

### 5. Terraform fmt Exit Code Handling
**Problem**: `terraform fmt -check` returns exit code 3 when files need formatting, not 1

**Fix**: Updated static_test.sh to handle exit code 3 correctly

**File Fixed**:
- `tests/terraform/static_test.sh`

### 6. Terraform Formatting
**Problem**: Terraform files needed formatting

**Fix**: Ran `terraform fmt -recursive` to format all files

**Files Formatted**:
- `main.tf`
- `modules/backup_job/main.tf`
- `modules/cluster/main.tf`
- `modules/lxc/main.tf`
- `modules/networking/main.tf`
- `modules/security/main.tf`
- `modules/snapshot/main.tf`
- `variables.tf`

## Test Status

After fixes:
- ✅ Bash tests: All passing (21 tests)
- ✅ Terraform static tests: fmt check passing
- ✅ Terraform formatting: All files formatted

## Running Tests

```bash
# All tests
make test

# Bash tests only
make test-bash

# Terraform tests only
make test-terraform
```

## Next Steps

1. Run full test suite: `make test`
2. Verify terraform behavior tests work with mocks
3. Add more test cases as needed
