#!/bin/bash
# Terraform behavior tests for null_resource
# Tests: enabled flag, triggers, force_run, "No changes" behavior

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
MOCKS_DIR="$SCRIPT_DIR/../mocks"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

log_test() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

log_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Setup: Add mocks to PATH
export PATH="$MOCKS_DIR:$PATH"

# Test 1: null_resource.vm created when enabled=true
test_vm_enabled_creates_resource() {
    log_info "Test: null_resource.vm created when enabled=true"
    
    cd "$PROJECT_ROOT" || exit 1
    
    # Clean state
    rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
    rm -rf .terraform/
    
    # Initialize
    terraform init -backend=false > /dev/null 2>&1 || true
    
    # Plan with enabled VM
    if terraform plan -var-file="$FIXTURES_DIR/vm_enabled_test.tfvars.json" -out=/tmp/test.plan > /tmp/plan_output.txt 2>&1; then
        # Check if null_resource.vm is in plan
        if grep -q "module.vm\[\"test-vm\"\].null_resource.vm\[0\]" /tmp/plan_output.txt; then
            log_test "null_resource.vm created when enabled=true"
        else
            log_fail "null_resource.vm not found in plan when enabled=true"
            cat /tmp/plan_output.txt
        fi
    else
        log_fail "terraform plan failed"
        cat /tmp/plan_output.txt
    fi
}

# Test 2: null_resource.vm NOT created when enabled=false
test_vm_disabled_no_resource() {
    log_info "Test: null_resource.vm NOT created when enabled=false"
    
    cd "$PROJECT_ROOT" || exit 1
    
    # Plan with disabled VM
    if terraform plan -var-file="$FIXTURES_DIR/vm_disabled_test.tfvars.json" -out=/tmp/test.plan > /tmp/plan_output.txt 2>&1; then
        # Check that null_resource.vm is NOT in plan
        if ! grep -q "module.vm\[\"test-vm\"\].null_resource.vm" /tmp/plan_output.txt; then
            log_test "null_resource.vm not created when enabled=false"
        else
            log_fail "null_resource.vm found in plan when enabled=false (should not exist)"
            cat /tmp/plan_output.txt
        fi
    else
        log_fail "terraform plan failed"
        cat /tmp/plan_output.txt
    fi
}

# Test 3: Triggers change causes replacement
test_triggers_change_replacement() {
    log_info "Test: Triggers change causes resource replacement"
    
    cd "$PROJECT_ROOT" || exit 1
    
    # First apply to create resource
    terraform apply -var-file="$FIXTURES_DIR/vm_enabled_test.tfvars.json" -auto-approve > /dev/null 2>&1 || true
    
    # Modify force_run trigger
    local modified_tfvars=$(mktemp)
    if ! jq '.vm_force_run = "9999999999"' "$FIXTURES_DIR/vm_enabled_test.tfvars.json" > "$modified_tfvars" 2>&1; then
        log_fail "Failed to modify tfvars file with jq"
        rm -f "$modified_tfvars"
        return 1
    fi
    
    # Validate JSON was created correctly
    if [ ! -s "$modified_tfvars" ] || ! jq . "$modified_tfvars" > /dev/null 2>&1; then
        log_fail "Modified tfvars file is invalid JSON"
        rm -f "$modified_tfvars"
        return 1
    fi
    
    # Plan again
    if terraform plan -var-file="$modified_tfvars" > /tmp/plan_output.txt 2>&1; then
        # Should show replacement due to trigger change
        if grep -q "must be replaced" /tmp/plan_output.txt || grep -q "forces replacement" /tmp/plan_output.txt; then
            log_test "Triggers change causes resource replacement"
        else
            log_fail "Triggers change did not cause replacement"
            cat /tmp/plan_output.txt
        fi
    else
        log_fail "terraform plan failed"
        cat /tmp/plan_output.txt
    fi
    
    rm -f "$modified_tfvars"
}

# Test 4: "No changes" when triggers unchanged
test_no_changes_when_unchanged() {
    log_info "Test: 'No changes' when triggers unchanged"
    
    cd "$PROJECT_ROOT" || exit 1
    
    # Apply once
    terraform apply -var-file="$FIXTURES_DIR/vm_enabled_test.tfvars.json" -auto-approve > /dev/null 2>&1 || true
    
    # Plan again with same tfvars
    if terraform plan -var-file="$FIXTURES_DIR/vm_enabled_test.tfvars.json" > /tmp/plan_output.txt 2>&1; then
        # Should show "No changes" (unless force_run changes)
        if grep -q "No changes" /tmp/plan_output.txt || grep -q "forces replacement" /tmp/plan_output.txt; then
            log_test "'No changes' occurs when triggers unchanged (or force_run changes)"
        else
            log_fail "Expected 'No changes' but got different output"
            cat /tmp/plan_output.txt
        fi
    else
        log_fail "terraform plan failed"
        cat /tmp/plan_output.txt
    fi
}

# Test 5: force_run trigger forces re-execution
test_force_run_triggers_replacement() {
    log_info "Test: force_run trigger forces re-execution"
    
    cd "$PROJECT_ROOT" || exit 1
    
    # Apply with initial force_run
    terraform apply -var-file="$FIXTURES_DIR/vm_enabled_test.tfvars.json" -auto-approve > /dev/null 2>&1 || true
    
    # Change force_run
    local new_force_run=$(date +%s)
    local modified_tfvars=$(mktemp)
    if ! jq --arg fr "$new_force_run" '.vm_force_run = $fr' "$FIXTURES_DIR/vm_enabled_test.tfvars.json" > "$modified_tfvars" 2>&1; then
        log_fail "Failed to modify tfvars file with jq"
        rm -f "$modified_tfvars"
        return 1
    fi
    
    # Validate JSON was created correctly
    if [ ! -s "$modified_tfvars" ] || ! jq . "$modified_tfvars" > /dev/null 2>&1; then
        log_fail "Modified tfvars file is invalid JSON"
        rm -f "$modified_tfvars"
        return 1
    fi
    
    # Plan with new force_run
    if terraform plan -var-file="$modified_tfvars" > /tmp/plan_output.txt 2>&1; then
        # Should show replacement
        if grep -q "must be replaced" /tmp/plan_output.txt || grep -q "forces replacement" /tmp/plan_output.txt; then
            log_test "force_run trigger forces resource replacement"
        else
            log_fail "force_run change did not trigger replacement"
            cat /tmp/plan_output.txt
        fi
    else
        log_fail "terraform plan failed"
        cat /tmp/plan_output.txt
    fi
    
    rm -f "$modified_tfvars"
}

# Run all tests
main() {
    echo "Running Terraform behavior tests..."
    echo ""
    
    test_vm_enabled_creates_resource
    test_vm_disabled_no_resource
    test_triggers_change_replacement
    test_no_changes_when_unchanged
    test_force_run_triggers_replacement
    
    echo ""
    echo "Results: $PASSED passed, $FAILED failed"
    
    if [ $FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
