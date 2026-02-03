# Testing Guide - ThinkDeploy Proxmox Platform

## Quick Start

```bash
# Run all tests
make test

# Run specific test suites
make test-bash          # Bash unit tests
make test-terraform     # Terraform tests
make test-integration   # Integration tests (requires flag)
```

## Test Structure

```
tests/
├── bash/                    # Bash unit tests (bats)
│   ├── json_build_test.bats      # JSON generation validation
│   ├── deploy_all_test.bats      # Deploy All logic
│   └── preflight_test.bats       # Preflight validation
├── terraform/               # Terraform tests
│   ├── fixtures/            # Test tfvars files
│   ├── static_test.sh       # fmt, validate, plan
│   └── behavior_test.sh     # null_resource behavior
└── mocks/                   # Mock executables
    ├── ssh                  # Mock SSH command
    ├── pvesh                # Mock pvesh command
    └── qm                   # Mock qm command
```

## Test Layers Explained

### Layer A: Bash Unit Tests

**Tool**: bats-core  
**Location**: `tests/bash/*.bats`

**What it tests**:
- JSON generation validity
- SSH key path expansion (`~` → absolute)
- Deploy All logic (zero VMs vs other resources)
- Preflight validation behavior
- Error handling with `set -euo pipefail`

**Example**:
```bash
@test "SSH key path should expand ~ to HOME" {
    local ssh_key="~/.ssh/id_rsa"
    ssh_key="${ssh_key/#\~/$HOME}"
    [[ "$ssh_key" != *"~"* ]]
    assert_success
}
```

### Layer B: Terraform Static Tests

**Tool**: terraform fmt, validate, plan  
**Location**: `tests/terraform/static_test.sh`

**What it tests**:
- `terraform fmt -check` (formatting)
- `terraform validate` (syntax)
- `terraform plan` with mock tfvars
- Missing variable detection

**Example**:
```bash
test_terraform_fmt() {
    terraform fmt -check -recursive
    assert_success
}
```

### Layer C: Terraform Behavior Tests

**Tool**: terraform plan + grep assertions  
**Location**: `tests/terraform/behavior_test.sh`

**What it tests**:
- `null_resource.vm` created when `enabled=true`
- `null_resource.vm` NOT created when `enabled=false`
- Triggers change causes replacement
- `force_run` trigger forces re-execution
- "No changes" occurs only when expected

**Example**:
```bash
test_vm_enabled_creates_resource() {
    terraform plan -var-file="fixtures/vm_enabled_test.tfvars.json"
    grep -q "null_resource.vm\[0\]" plan_output.txt
    assert_success
}
```

### Layer D: Integration Tests (Optional)

**Tool**: Mock SSH/pvesh scripts  
**Location**: `tests/mocks/`

**What it tests**:
- Correct pvesh commands generated
- SSH arguments correct
- VM existence check uses correct API path

**Note**: Real Proxmox tests only with `PROXMOX_INTEGRATION_TESTS=true`

## Running Tests Locally

### Prerequisites

```bash
# Install bats-core
# Ubuntu/Debian:
sudo apt-get install bats

# macOS:
brew install bats-core

# Or from source:
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

### Run All Tests

```bash
make test
```

### Run Specific Suites

```bash
# Bash tests only
make test-bash

# Terraform static tests
make test-terraform-static

# Terraform behavior tests
make test-terraform-behavior

# All terraform tests
make test-terraform
```

### Run Individual Test Files

```bash
# Single bats file
bats tests/bash/json_build_test.bats

# Single terraform test script
bash tests/terraform/static_test.sh
```

## Mock Scripts

Mock scripts in `tests/mocks/` simulate SSH and pvesh commands:

- **ssh**: Logs arguments, returns mock responses
- **pvesh**: Simulates Proxmox API responses
- **qm**: Simulates qm command responses

**Usage**:
```bash
export PATH="$(pwd)/tests/mocks:$PATH"
terraform plan  # Uses mock commands
```

## CI Integration

### GitHub Actions

See `.github/workflows/test.yml` for complete CI setup.

**Features**:
- Runs on push/PR
- No Proxmox cluster required
- Fast execution (< 2 minutes)
- Parallel test execution
- Artifact upload on failure

### Local CI Simulation

```bash
# Simulate CI environment
export CI=true
make test
```

## Test Fixtures

Test tfvars files in `tests/terraform/fixtures/`:

- `vm_enabled_test.tfvars.json` - VM with enabled=true
- `vm_disabled_test.tfvars.json` - VM with enabled=false
- `deploy_all_no_vm_test.tfvars.json` - Storage/networking only

## Troubleshooting

### Tests fail with "bats not found"

```bash
# Install bats-core (see Prerequisites above)
```

### Terraform tests fail with "variable not set"

```bash
# Ensure test fixtures are valid JSON
jq . tests/terraform/fixtures/*.json
```

### Mock scripts not working

```bash
# Ensure mocks are executable
chmod +x tests/mocks/*

# Check PATH includes mocks
export PATH="$(pwd)/tests/mocks:$PATH"
which ssh  # Should show tests/mocks/ssh
```

### "No changes" test fails

This is expected if `force_run` changes between runs. The test validates that triggers change causes replacement.

## Adding New Tests

### Bash Test

Create `tests/bash/new_test.bats`:

```bash
#!/usr/bin/env bats
load 'test_helper.bash'

@test "my new test" {
    # Test code
    assert_success
}
```

### Terraform Test

Add to `tests/terraform/behavior_test.sh`:

```bash
test_my_new_behavior() {
    log_info "Test: My new behavior"
    # Test code
    log_test "Behavior validated"
}
```

## Test Coverage Goals

- **Bash tests**: 80%+ of setup.sh functions
- **Terraform static**: 100% of modules validated
- **Terraform behavior**: All null_resource scenarios
- **Integration**: Critical paths only (mocked)

## Best Practices

1. **Keep tests fast** (< 30 seconds per suite)
2. **Use mocks** for external dependencies
3. **Test behavior, not implementation**
4. **Clear test names** describing what they validate
5. **Isolate tests** (no shared state)
6. **Clean up** after tests (use teardown functions)
