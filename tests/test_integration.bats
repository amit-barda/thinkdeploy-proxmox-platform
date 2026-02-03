#!/usr/bin/env bats

# Integration tests for the full workflow

load 'test_helper.bash'

setup() {
    test_helper_setup
    cd "${BATS_TEST_DIRNAME}/.."
}

@test "setup.sh should be executable" {
    [ -x "setup.sh" ]
}

@test "setup.sh should have shebang" {
    run head -n 1 setup.sh
    [ "$status" -eq 0 ]
    [[ "$output" == "#!/bin/bash"* ]]
}

@test "setup.sh should set error handling" {
    run grep -q "set -euo pipefail" setup.sh
    [ "$status" -eq 0 ]
}

@test "setup.sh should define log function" {
    run grep -q "^log()" setup.sh
    [ "$status" -eq 0 ]
}

@test "setup.sh should define error_exit function" {
    run grep -q "^error_exit()" setup.sh
    [ "$status" -eq 0 ]
}

@test "setup.sh should define all configuration functions" {
    run grep -q "^configure_cluster()" setup.sh
    [ "$status" -eq 0 ]
    
    run grep -q "^configure_compute()" setup.sh
    [ "$status" -eq 0 ]
    
    run grep -q "^configure_networking()" setup.sh
    [ "$status" -eq 0 ]
    
    run grep -q "^configure_storage()" setup.sh
    [ "$status" -eq 0 ]
    
    run grep -q "^configure_backup()" setup.sh
    [ "$status" -eq 0 ]
    
    run grep -q "^configure_security()" setup.sh
    [ "$status" -eq 0 ]
}

@test "setup.sh should validate prerequisites" {
    run grep -q "command -v terraform" setup.sh
    [ "$status" -eq 0 ]
}

@test "setup.sh should handle Proxmox CLI detection" {
    run grep -q "PROXMOX_CLI_METHOD" setup.sh
    [ "$status" -eq 0 ]
}

@test "setup.sh should build terraform command" {
    run grep -q "terraform apply" setup.sh
    [ "$status" -eq 0 ]
}

@test "setup.sh should validate JSON before deployment" {
    run grep -q "jq ." setup.sh
    [ "$status" -eq 0 ]
}
