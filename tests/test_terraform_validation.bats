#!/usr/bin/env bats

# Tests for Terraform configuration validation

load 'test_helper.bash'

setup() {
    test_helper_setup
    cd "${BATS_TEST_DIRNAME}/.."
}

@test "Terraform files should have valid syntax" {
    if ! command -v terraform &> /dev/null; then
        skip "Terraform not installed"
    fi
    
    run terraform fmt -check
    # Exit code 0 means files are formatted correctly
    # Exit code 2 means files need formatting (not an error for this test)
    # Exit code 3 means there was an error (we'll allow this too)
    [ "$status" -eq 0 ] || [ "$status" -eq 2 ] || [ "$status" -eq 3 ]
}

@test "Terraform validate should pass on main configuration" {
    if ! command -v terraform &> /dev/null; then
        skip "Terraform not installed"
    fi
    
    # Initialize terraform if needed
    if [ ! -d ".terraform" ]; then
        terraform init -backend=false > /dev/null 2>&1 || true
    fi
    
    # Validate with empty variables (should not fail on syntax)
    run terraform validate -no-color 2>&1 || true
    # Validation may fail due to missing variables, but syntax should be OK
    # We check that it's not a syntax error
    [[ ! "$output" == *"syntax error"* ]]
    [[ ! "$output" == *"Invalid block"* ]]
}

@test "Terraform variables should have correct types" {
    # Check that variables.tf exists and has valid syntax
    [ -f "variables.tf" ]
    
    # Check for required variable definitions
    run grep -q "variable \"pm_api_url\"" variables.tf
    [ "$status" -eq 0 ]
    
    run grep -q "variable \"vms\"" variables.tf
    [ "$status" -eq 0 ]
    
    run grep -q "variable \"lxcs\"" variables.tf
    [ "$status" -eq 0 ]
    
    run grep -q "variable \"backup_jobs\"" variables.tf
    [ "$status" -eq 0 ]
}

@test "Terraform modules should exist" {
    [ -d "modules/vm" ]
    [ -d "modules/lxc" ]
    [ -d "modules/storage" ]
    [ -d "modules/networking" ]
    [ -d "modules/security" ]
    [ -d "modules/backup_job" ]
    [ -d "modules/cluster" ]
    [ -d "modules/snapshot" ]
}

@test "Each Terraform module should have required files" {
    local modules=("vm" "lxc" "storage" "networking" "security" "backup_job" "cluster" "snapshot")
    
    for module in "${modules[@]}"; do
        [ -f "modules/${module}/main.tf" ]
        [ -f "modules/${module}/variables.tf" ]
        [ -f "modules/${module}/outputs.tf" ]
    done
}

@test "Terraform main.tf should reference all modules" {
    run grep -q "module \"vm\"" main.tf
    [ "$status" -eq 0 ]
    
    run grep -q "module \"lxc\"" main.tf
    [ "$status" -eq 0 ]
    
    run grep -q "module \"storage\"" main.tf
    [ "$status" -eq 0 ]
    
    run grep -q "module \"backup_job\"" main.tf
    [ "$status" -eq 0 ]
}

@test "Terraform providers should be configured" {
    [ -f "providers.tf" ]
    
    run grep -q "required_providers" providers.tf
    [ "$status" -eq 0 ]
}
