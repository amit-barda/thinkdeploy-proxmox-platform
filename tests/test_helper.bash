#!/usr/bin/env bash

# Test helper functions for BATS tests
# This file is sourced by all test files

# Load BATS helper functions
load '/usr/lib/bats-support/load.bash'
load '/usr/lib/bats-assert/load.bash'

# Test fixtures directory (adjust path based on test location)
if [ -d "${BATS_TEST_DIRNAME}/../fixtures" ]; then
    TEST_FIXTURES_DIR="${BATS_TEST_DIRNAME}/../fixtures"
else
    TEST_FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"
fi
TEST_TMP_DIR="${BATS_TEST_DIRNAME}/../tmp"

# Setup function run before each test
test_helper_setup() {
    # Create temporary directory for test artifacts
    mkdir -p "$TEST_TMP_DIR"
    
    # Export test environment variables
    export TEST_MODE=1
    export LOG_FILE="${TEST_TMP_DIR}/test-$(date +%s).log"
    
    # Mock terraform command if not available
    if ! command -v terraform &> /dev/null; then
        export PATH="${TEST_TMP_DIR}:${PATH}"
        create_mock_terraform
    fi
    
    # Mock jq command if not available
    if ! command -v jq &> /dev/null; then
        create_mock_jq
    fi
}

# Default setup function (can be overridden by tests)
setup() {
    test_helper_setup
}

# Teardown function run after each test
teardown() {
    # Clean up temporary files
    rm -rf "$TEST_TMP_DIR"/* 2>/dev/null || true
}

# Create a mock terraform binary
create_mock_terraform() {
    cat > "${TEST_TMP_DIR}/terraform" << 'EOF'
#!/bin/bash
case "$1" in
    version)
        echo '{"terraform_version":"1.6.0"}'
        ;;
    init)
        echo "Terraform initialized"
        exit 0
        ;;
    validate)
        exit 0
        ;;
    plan)
        echo "Plan: 0 to add, 0 to change, 0 to destroy"
        exit 0
        ;;
    *)
        echo "Mock terraform: $*"
        exit 0
        ;;
esac
EOF
    chmod +x "${TEST_TMP_DIR}/terraform"
}

# Create a mock jq binary
create_mock_jq() {
    cat > "${TEST_TMP_DIR}/jq" << 'EOF'
#!/bin/bash
# Simple mock jq that handles basic JSON operations
if [ "$1" = "-r" ] && [ "$2" = ".terraform_version" ]; then
    echo "1.6.0"
elif [ "$1" = "-r" ] && [ "$2" = ".name" ]; then
    echo "test-cluster"
elif [ "$1" = "-r" ] && [ "$2" = ".primary_node" ]; then
    echo "pve1"
else
    cat
fi
EOF
    chmod +x "${TEST_TMP_DIR}/jq"
}

# Source the setup.sh script functions
source_setup_functions() {
    # Extract and source only the functions we need for testing
    # This avoids running the main script logic
    local setup_script="${BATS_TEST_DIRNAME}/../setup.sh"
    
    # Source the script in a subshell to extract functions
    (
        source "$setup_script" 2>/dev/null || true
        declare -f > "${TEST_TMP_DIR}/functions.sh"
    ) || true
    
    # Source the functions file
    if [ -f "${TEST_TMP_DIR}/functions.sh" ]; then
        source "${TEST_TMP_DIR}/functions.sh" 2>/dev/null || true
    fi
    
    # Directly source the setup script but prevent execution
    # We'll use a wrapper that sources functions only
    if [ -f "$setup_script" ]; then
        # Extract function definitions using sed
        sed -n '/^[a-zA-Z_][a-zA-Z0-9_]*()/,/^}$/p' "$setup_script" > "${TEST_TMP_DIR}/extracted_functions.sh" 2>/dev/null || true
        source "${TEST_TMP_DIR}/extracted_functions.sh" 2>/dev/null || true
    fi
}

# Helper to run a function from setup.sh
run_setup_function() {
    local func_name=$1
    shift
    local args=("$@")
    
    # Source setup.sh functions
    source_setup_functions
    
    # Run the function
    "$func_name" "${args[@]}"
}

# Assert that a log file contains a pattern
assert_log_contains() {
    local pattern=$1
    local log_file=${2:-$LOG_FILE}
    
    if [ -f "$log_file" ]; then
        assert grep -q "$pattern" "$log_file"
    else
        fail "Log file $log_file does not exist"
    fi
}

# Assert JSON is valid
assert_valid_json() {
    local json_string=$1
    if command -v jq &> /dev/null; then
        echo "$json_string" | jq . > /dev/null 2>&1
        assert_success
    else
        # Basic JSON validation
        [[ "$json_string" =~ ^\{.*\}$ ]] || [[ "$json_string" =~ ^\[.*\]$ ]]
        assert_success
    fi
}

# Create test input file
create_test_input() {
    local content=$1
    echo "$content" > "${TEST_TMP_DIR}/test_input.txt"
    echo "${TEST_TMP_DIR}/test_input.txt"
}
