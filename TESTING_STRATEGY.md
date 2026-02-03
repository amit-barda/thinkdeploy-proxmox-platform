# ThinkDeploy Proxmox Platform - Testing Strategy

## Overview

Comprehensive testing strategy for Terraform-based Proxmox automation using `null_resource` + `local-exec` with SSH + `pvesh` commands.

## Testing Layers

### Layer A: Bash Unit Tests (setup.sh)
**Tool**: bats-core  
**Purpose**: Test bash script logic, JSON generation, validation functions

**Tests**:
- SSH key path expansion (`~` → absolute path)
- JSON generation validity (tfvars file structure)
- Deploy All logic (enabled VMs vs other resources)
- Preflight validation behavior
- Error handling with `set -euo pipefail`
- Variable expansion and quoting

### Layer B: Terraform Static Tests
**Tool**: terraform fmt, validate, plan  
**Purpose**: Detect configuration errors before runtime

**Tests**:
- `terraform fmt -check` (formatting)
- `terraform validate` (syntax and structure)
- `terraform plan` with mock tfvars (detect missing variables)
- Count/for_each logic validation
- `enabled` flag handling
- Module wiring correctness

### Layer C: Terraform Behavior Tests (null_resource)
**Tool**: terraform plan + grep assertions  
**Purpose**: Validate null_resource behavior and triggers

**Tests**:
- `null_resource.vm` created when `enabled=true`
- `null_resource.vm` not created when `enabled=false`
- Triggers change causes resource replacement
- `force_run` trigger forces re-execution
- "No changes" occurs only when expected

### Layer D: Integration Tests (Optional/Tagged)
**Tool**: Mock SSH/pvesh scripts  
**Purpose**: Validate correct commands are generated

**Tests**:
- Correct pvesh commands generated
- SSH arguments correct
- VM existence check uses correct API path
- Error handling in provisioners

**Note**: Real Proxmox tests only run with `PROXMOX_INTEGRATION_TESTS=true`

## Test Structure

```
tests/
├── bash/                          # Bash unit tests (bats)
│   ├── setup_test.bats           # setup.sh core functions
│   ├── preflight_test.bats       # Preflight validation
│   ├── json_build_test.bats      # JSON generation
│   └── deploy_all_test.bats      # Deploy All logic
├── terraform/                     # Terraform tests
│   ├── fixtures/                  # Test tfvars files
│   │   ├── vm_enabled_test.tfvars.json
│   │   ├── vm_disabled_test.tfvars.json
│   │   ├── deploy_all_no_vm_test.tfvars.json
│   │   └── force_run_test.tfvars.json
│   ├── plan_assertions.sh        # Plan output assertions
│   ├── static_test.sh             # fmt + validate
│   └── behavior_test.sh           # null_resource behavior
├── mocks/                         # Mock executables
│   ├── ssh                        # Mock SSH command
│   ├── pvesh                      # Mock pvesh command
│   └── qm                         # Mock qm command
├── fixtures/                      # Test data (existing)
│   ├── sample_vm_config.json
│   ├── sample_lxc_config.json
│   └── sample_backup_config.json
├── test_helper.bash               # BATS helpers (existing)
└── run_tests.sh                   # Test runner (existing)
```

## Running Tests

### Local Development
```bash
make test                    # Run all tests
make test-bash              # Bash unit tests only
make test-terraform         # Terraform tests only
make test-integration       # Integration tests (requires flag)
```

### CI/CD
```bash
# Default (no Proxmox required)
make test

# With real Proxmox (optional)
PROXMOX_INTEGRATION_TESTS=true make test-integration
```

## Test Coverage Goals

- **Bash tests**: 80%+ coverage of setup.sh functions
- **Terraform static**: 100% of modules validated
- **Terraform behavior**: All null_resource scenarios
- **Integration**: Critical paths only (mocked)

## CI Integration

Tests run in GitHub Actions with:
- No root access required
- No Proxmox cluster required (by default)
- Fast execution (< 2 minutes)
- Clear pass/fail reporting
