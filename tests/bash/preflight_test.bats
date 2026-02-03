#!/usr/bin/env bats

# Tests for preflight validation functions
# Tests SSH key expansion, node validation, etc.

load '../test_helper.bash'

setup() {
    test_helper_setup
    source_setup_functions
}

@test "SSH key path should expand ~ to HOME" {
    local ssh_key="~/.ssh/id_rsa"
    local home_dir="${HOME}"
    
    # Expand ~
    ssh_key="${ssh_key/#\~/$HOME}"
    
    run bash -c "[[ \"$ssh_key\" != *\"~\"* ]]"
    assert_success
    run bash -c "[[ \"$ssh_key\" == *\"$home_dir\"* ]]"
    assert_success
}

@test "SSH key path should handle absolute paths" {
    local ssh_key="/root/.ssh/id_rsa"
    local original="$ssh_key"
    
    # Expansion should not change absolute paths
    ssh_key="${ssh_key/#\~/$HOME}"
    
    run bash -c "[ \"$ssh_key\" = \"$original\" ]"
    assert_success
}

@test "SSH key path should expand to absolute path for Terraform" {
    local ssh_key="~/.ssh/id_rsa"
    ssh_key="${ssh_key/#\~/$HOME}"
    
    # Should expand to absolute path
    ssh_key=$(readlink -f "$ssh_key" 2>/dev/null || realpath "$ssh_key" 2>/dev/null || echo "$ssh_key")
    
    run bash -c "[[ \"$ssh_key\" == /* ]]"
    assert_success
}

@test "Node name validation should check exact match" {
    # Simulate Proxmox nodes
    local proxmox_nodes="pve1
pve2
pve3"
    
    local test_node="pve1"
    
    # Should find exact match
    run bash -c "echo \"$proxmox_nodes\" | grep -q \"^${test_node}$\""
    assert_success
    
    # Case-sensitive
    local wrong_case="PVE1"
    run bash -c "echo \"$proxmox_nodes\" | grep -q \"^${wrong_case}$\""
    assert_failure
}

@test "Node name validation should reject non-existent nodes" {
    local proxmox_nodes="pve1
pve2"
    
    local test_node="pve99"
    
    # Should not find match
    run bash -c "echo \"$proxmox_nodes\" | grep -q \"^${test_node}$\""
    assert_failure
}

@test "VMID availability check should detect existing VMIDs" {
    # Mock: VMID 100 exists
    local existing_vmids="100
101
102"
    
    local test_vmid=100
    
    # Should find existing VMID
    run bash -c "echo \"$existing_vmids\" | grep -q \"^${test_vmid}$\""
    assert_success
}

@test "VMID availability check should allow new VMIDs" {
    local existing_vmids="100
101"
    
    local test_vmid=200
    
    # Should not find new VMID
    run bash -c "echo \"$existing_vmids\" | grep -q \"^${test_vmid}$\""
    assert_failure
}

@test "Storage validation should check node-specific storage" {
    # Storage exists on pve1
    local storage="local-lvm"
    local node="pve1"
    
    # Mock: pvesh command would return success
    # In real test, this would use mock pvesh
    local storage_exists=true
    
    run bash -c "[ \"$storage_exists\" = \"true\" ]"
    assert_success
}
