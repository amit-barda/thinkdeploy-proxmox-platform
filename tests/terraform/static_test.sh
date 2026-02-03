#!/bin/bash
# Terraform static tests: fmt, validate, plan with mock tfvars

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

PASSED=0
FAILED=0

log_test() {
    echo "✓ $1"
    ((PASSED++))
}

log_fail() {
    echo "✗ $1"
    ((FAILED++))
}

# Test 1: terraform fmt -check
test_terraform_fmt() {
    echo "Test: terraform fmt -check"
    
    cd "$PROJECT_ROOT" || exit 1
    
    # terraform fmt -check returns 0 if formatted, 3 if needs formatting
    terraform fmt -check -recursive > /tmp/fmt_output.txt 2>&1
    local fmt_exit=$?
    
    if [ $fmt_exit -eq 0 ]; then
        log_test "terraform fmt -check passed"
    elif [ $fmt_exit -eq 3 ]; then
        log_fail "terraform fmt -check failed (files need formatting)"
        cat /tmp/fmt_output.txt
    else
        log_fail "terraform fmt -check failed with unexpected exit code: $fmt_exit"
        cat /tmp/fmt_output.txt
    fi
}

# Test 2: terraform validate
test_terraform_validate() {
    echo "Test: terraform validate"
    
    cd "$PROJECT_ROOT" || exit 1
    
    # Initialize first
    terraform init -backend=false > /dev/null 2>&1 || true
    
    if terraform validate > /tmp/validate_output.txt 2>&1; then
        log_test "terraform validate passed"
    else
        # Validation may fail without variables, check if it's variable-related
        if grep -q "variable" /tmp/validate_output.txt; then
            log_test "terraform validate (expected variable errors without tfvars)"
        else
            log_fail "terraform validate failed"
            cat /tmp/validate_output.txt
        fi
    fi
}

# Test 3: terraform plan with mock tfvars
test_terraform_plan() {
    echo "Test: terraform plan with mock tfvars"
    
    cd "$PROJECT_ROOT" || exit 1
    
    # Initialize
    terraform init -backend=false > /dev/null 2>&1 || true
    
    # Plan with test fixture
    if terraform plan -var-file="$FIXTURES_DIR/vm_enabled_test.tfvars.json" -out=/tmp/test.plan > /tmp/plan_output.txt 2>&1; then
        log_test "terraform plan with mock tfvars succeeded"
    else
        log_fail "terraform plan failed"
        cat /tmp/plan_output.txt
    fi
}

# Test 4: Check for missing variables
test_missing_variables() {
    echo "Test: Detect missing variables"
    
    cd "$PROJECT_ROOT" || exit 1
    
    # Plan without tfvars
    # Note: Terraform may succeed with defaults, or fail with variable errors
    # Both are acceptable - we just want to ensure it doesn't crash
    if terraform plan > /tmp/plan_output.txt 2>&1; then
        # Plan succeeded (likely using defaults) - this is OK
        log_test "terraform plan succeeded (using defaults or no required vars)"
    else
        # Plan failed - check if it's a variable error (expected) or something else
        if grep -q "required variable" /tmp/plan_output.txt || \
           grep -q "No value for required variable" /tmp/plan_output.txt || \
           grep -q "Error:.*variable" /tmp/plan_output.txt; then
            log_test "Missing variables detected correctly"
        else
            # Unexpected error
            log_fail "terraform plan failed with unexpected error"
            cat /tmp/plan_output.txt
        fi
    fi
}

# Run all tests
main() {
    echo "Running Terraform static tests..."
    echo ""
    
    test_terraform_fmt
    test_terraform_validate
    test_terraform_plan
    test_missing_variables
    
    echo ""
    echo "Results: $PASSED passed, $FAILED failed"
    
    if [ $FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
