#!/usr/bin/env bats

# Tests for validation and utility functions in setup.sh

load 'test_helper.bash'

# Source the setup.sh script to get functions
setup() {
    test_helper_setup
    # Source setup.sh functions (extract only function definitions)
    local setup_script="${BATS_TEST_DIRNAME}/../setup.sh"
    if [ -f "$setup_script" ]; then
        # Extract function definitions - match from function name to closing brace
        # Use a more robust method that handles nested braces
        awk '/^validate_ip\(\)/,/^}$/ {print} /^log\(\)/,/^}$/ {print} /^error_exit\(\)/,/^}$/ {print} /^warning\(\)/,/^}$/ {print}' "$setup_script" > "${TEST_TMP_DIR}/functions.sh" 2>/dev/null || true
        source "${TEST_TMP_DIR}/functions.sh" 2>/dev/null || true
    fi
}

@test "validate_ip should accept valid IP addresses" {
    # Test valid IP addresses
    run validate_ip "192.168.1.1"
    [ "$status" -eq 0 ]
    
    run validate_ip "10.0.0.1"
    [ "$status" -eq 0 ]
    
    run validate_ip "172.16.0.1"
    [ "$status" -eq 0 ]
    
    run validate_ip "255.255.255.255"
    [ "$status" -eq 0 ]
    
    run validate_ip "0.0.0.0"
    [ "$status" -eq 0 ]
}

@test "validate_ip should reject invalid IP addresses" {
    # Test invalid IP addresses (format issues that regex catches)
    run validate_ip "192.168.1"
    [ "$status" -eq 1 ]
    
    run validate_ip "192.168.1.1.1"
    [ "$status" -eq 1 ]
    
    run validate_ip "not.an.ip.address"
    [ "$status" -eq 1 ]
    
    run validate_ip ""
    [ "$status" -eq 1 ]
    
    run validate_ip "192.168.1."
    [ "$status" -eq 1 ]
    
    run validate_ip "abc.def.ghi.jkl"
    [ "$status" -eq 1 ]
}

@test "log function should write to log file" {
    local test_log="${TEST_TMP_DIR}/test.log"
    export LOG_FILE="$test_log"
    
    log "Test log message"
    
    [ -f "$test_log" ]
    run grep -q "Test log message" "$test_log"
    [ "$status" -eq 0 ]
}

@test "log function should include timestamp" {
    local test_log="${TEST_TMP_DIR}/test.log"
    export LOG_FILE="$test_log"
    
    log "Timestamp test"
    
    run grep -E '\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]' "$test_log"
    [ "$status" -eq 0 ]
}

@test "error_exit should log error and exit" {
    local test_log="${TEST_TMP_DIR}/test.log"
    export LOG_FILE="$test_log"
    
    # Run in subshell to avoid exiting the test
    (error_exit "Test error message" 2>&1) || true
    
    [ -f "$test_log" ]
    run grep -q "ERROR: Test error message" "$test_log"
    [ "$status" -eq 0 ]
}

@test "warning function should log warning" {
    local test_log="${TEST_TMP_DIR}/test.log"
    export LOG_FILE="$test_log"
    
    warning "Test warning message"
    
    [ -f "$test_log" ]
    run grep -q "WARNING: Test warning message" "$test_log"
    [ "$status" -eq 0 ]
}

@test "warning function should output to stderr" {
    local test_log="${TEST_TMP_DIR}/test.log"
    export LOG_FILE="$test_log"
    
    run warning "Test warning"
    [ "$status" -eq 0 ]
    # Check that warning emoji is in output
    [[ "$output" == *"⚠️"* ]]
}
