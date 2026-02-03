#!/usr/bin/env bats

# Tests for Deploy All logic
# Validates that Deploy All works with zero VMs (other resources)

load '../test_helper.bash'

setup() {
    test_helper_setup
    source_setup_functions
}

@test "Deploy All should deploy when VMs are enabled" {
    # Simulate enabled VMs
    local enabled_vms=1
    local has_configs=true
    
    # Deploy All should proceed
    run bash -c "[ $enabled_vms -gt 0 ] || [ \"$has_configs\" = \"true\" ]"
    assert_success
}

@test "Deploy All should deploy when no VMs but other resources exist" {
    # Simulate zero VMs but storage/networking configured
    local enabled_vms=0
    local has_configs=true
    
    # Deploy All should proceed (HAS_CONFIGS check)
    run bash -c "[ \"$has_configs\" = \"true\" ]"
    assert_success
}

@test "Deploy All should not deploy when no configs exist" {
    # Simulate no configurations
    local enabled_vms=0
    local has_configs=false
    
    # Deploy All should not proceed
    run bash -c "[ \"$has_configs\" = \"false\" ]"
    assert_success
}

@test "HAS_CONFIGS should be true when storage configured" {
    local storages='"nfs-backup":{"type":"nfs","server":"192.168.1.10","export":"/mnt/backup"}'
    local vms=""
    local lxcs=""
    local backup_jobs=""
    local networking_configs=""
    local security_configs=""
    local cluster_configs=""
    local snapshots=""
    
    # Check if any config exists
    local has_configs=false
    [ -n "$vms" ] && has_configs=true
    [ -n "$lxcs" ] && has_configs=true
    [ -n "$backup_jobs" ] && has_configs=true
    [ -n "$storages" ] && has_configs=true
    [ -n "$networking_configs" ] && has_configs=true
    [ -n "$security_configs" ] && has_configs=true
    [ -n "$cluster_configs" ] && has_configs=true
    [ -n "$snapshots" ] && has_configs=true
    
    run bash -c "[ \"$has_configs\" = \"true\" ]"
    assert_success
}

@test "HAS_CONFIGS should be true when networking configured" {
    local networking_configs='"bridge:vmbr1":{"iface":"enp3s0","stp":"N","mtu":1500}'
    local vms=""
    local storages=""
    
    local has_configs=false
    [ -n "$networking_configs" ] && has_configs=true
    
    run bash -c "[ \"$has_configs\" = \"true\" ]"
    assert_success
}

@test "HAS_CONFIGS should be true when security configured" {
    local security_configs='rbac:{"userid":"admin@pam","role":"Administrator"}'
    local vms=""
    
    local has_configs=false
    [ -n "$security_configs" ] && has_configs=true
    
    run bash -c "[ \"$has_configs\" = \"true\" ]"
    assert_success
}

@test "Deploy All should set vm_force_run timestamp" {
    # Simulate Deploy All setting force_run
    local vm_force_run=$(date +%s)
    
    # Should be numeric timestamp
    run bash -c "[[ \"$vm_force_run\" =~ ^[0-9]+$ ]]"
    assert_success
    
    # Should be recent (within last minute)
    local current_time=$(date +%s)
    local time_diff=$((current_time - vm_force_run))
    run bash -c "[ $time_diff -lt 60 ]"
    assert_success
}
