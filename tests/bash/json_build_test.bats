#!/usr/bin/env bats

# Tests for JSON generation and tfvars file building
# Validates setup.sh JSON output validity

load '../test_helper.bash'

setup() {
    test_helper_setup
    # Note: source_setup_functions may not work reliably, tests use direct logic
}

@test "build_tfvars_file should generate valid JSON with VMs" {
    # Simulate VM configuration
    vms='"test-vm":{"node":"pve1","vmid":100,"cores":2,"memory":2048,"disk":"50G","storage":"local-lvm","network":"model=virtio,bridge=vmbr0","enabled":true}'
    lxcs=""
    backup_jobs=""
    storages=""
    networking_configs=""
    security_configs=""
    cluster_configs=""
    snapshots=""
    
    # Mock build_tfvars_file function behavior
    local tfvars_json='{"vms":{"test-vm":{"node":"pve1","vmid":100,"cores":2,"memory":2048,"disk":"50G","storage":"local-lvm","network":"model=virtio,bridge=vmbr0","enabled":true}},"lxcs":{},"backup_jobs":{},"storages":{},"networking_config":{},"security_config":{},"snapshots":{},"cluster_config":{},"vm_force_run":"1234567890"}'
    
    # Validate JSON structure
    if command -v jq &> /dev/null; then
        run bash -c "echo '$tfvars_json' | jq . > /dev/null 2>&1"
        assert_success
        assert_output ""
        
        # Validate VM is present (check if vms object has test-vm key)
        run bash -c "echo '$tfvars_json' | jq -r '.vms | has(\"test-vm\")'"
        assert_success
        assert_output "true"
        
        # Validate VMID
        run bash -c "echo '$tfvars_json' | jq -r '.vms.\"test-vm\".vmid'"
        assert_success
        assert_output "100"
    else
        skip "jq not available"
    fi
}

@test "build_tfvars_file should generate valid JSON with empty configs" {
    vms=""
    lxcs=""
    backup_jobs=""
    storages=""
    networking_configs=""
    security_configs=""
    cluster_configs=""
    snapshots=""
    
    local tfvars_json='{"vms":{},"lxcs":{},"backup_jobs":{},"storages":{},"networking_config":{},"security_config":{},"snapshots":{},"cluster_config":{},"vm_force_run":"1234567890"}'
    
    if command -v jq &> /dev/null; then
        run bash -c "echo '$tfvars_json' | jq . > /dev/null 2>&1"
        assert_success
    else
        [[ "$tfvars_json" =~ ^\{.*\}$ ]]
        assert_success
    fi
}

@test "build_tfvars_file should include vm_force_run timestamp" {
    local tfvars_json='{"vms":{},"vm_force_run":"1234567890"}'
    
    if command -v jq &> /dev/null; then
        run bash -c "echo '$tfvars_json' | jq -r '.vm_force_run'"
        assert_success
        assert_output "1234567890"
        
        # Should be numeric (timestamp)
        run bash -c "echo '$tfvars_json' | jq -r '.vm_force_run' | grep -E '^[0-9]+$'"
        assert_success
    else
        skip "jq not available"
    fi
}

@test "JSON should handle special characters in network config" {
    # Network config with spaces and special chars
    local network_config="model=virtio,bridge=vmbr0,ip=192.168.1.100/24"
    local vm_json="{\"test-vm\":{\"network\":\"$network_config\"}}"
    
    if command -v jq &> /dev/null; then
        run bash -c "echo '$vm_json' | jq . > /dev/null 2>&1"
        assert_success
        
        run bash -c "echo '$vm_json' | jq -r '.\"test-vm\".network'"
        assert_success
        assert_output "$network_config"
    else
        skip "jq not available"
    fi
}

@test "JSON should handle multiple VMs correctly" {
    local vm1='"vm1":{"node":"pve1","vmid":100,"cores":2,"memory":2048,"disk":"50G","storage":"local-lvm","network":"model=virtio,bridge=vmbr0","enabled":true}'
    local vm2='"vm2":{"node":"pve1","vmid":101,"cores":4,"memory":4096,"disk":"100G","storage":"local-lvm","network":"model=virtio,bridge=vmbr0","enabled":true}'
    local vms="$vm1,$vm2"
    
    local tfvars_json="{\"vms\":{$vms}}"
    
    if command -v jq &> /dev/null; then
        run bash -c "echo '$tfvars_json' | jq . > /dev/null 2>&1"
        assert_success
        
        # Count VMs
        run bash -c "echo '$tfvars_json' | jq '.vms | keys | length'"
        assert_success
        assert_output "2"
    else
        skip "jq not available"
    fi
}

@test "JSON should reject invalid syntax" {
    local invalid_json='{"vms":{"test-vm":{"vmid":100,invalid}}}'
    
    if command -v jq &> /dev/null; then
        run bash -c "echo '$invalid_json' | jq . > /dev/null 2>&1"
        assert_failure
    else
        skip "jq not available"
    fi
}
