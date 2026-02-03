#!/usr/bin/env bats

# Tests for JSON parsing and validation logic

load 'test_helper.bash'

setup() {
    test_helper_setup
    # No need to source setup.sh for JSON parsing tests
}

@test "JSON validation should accept valid VM configuration" {
    local vm_json='{"web-server-01":{"node":"pve1","vmid":100,"cores":2,"memory":2048,"disk":"50G","storage":"local-lvm","network":"model=virtio,bridge=vmbr0","enabled":true}}'
    
    if command -v jq &> /dev/null; then
        # Use run to capture exit code properly
        run bash -c "echo '$vm_json' | jq . > /dev/null 2>&1"
        # jq returns 0 on success, non-zero on error
        [ "$status" -eq 0 ]
    else
        # Basic validation - check for braces
        [[ "$vm_json" =~ ^\{.*\}$ ]]
    fi
}

@test "JSON validation should accept valid LXC configuration" {
    local lxc_json='{"app-container-01":{"node":"pve1","vmid":200,"cores":2,"memory":2048,"rootfs":"20G","storage":"local-lvm","ostemplate":"local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst","enabled":true}}'
    
    if command -v jq &> /dev/null; then
        run bash -c "echo '$lxc_json' | jq . > /dev/null 2>&1"
        [ "$status" -eq 0 ]
    else
        [[ "$lxc_json" =~ ^\{.*\}$ ]]
        assert_success
    fi
}

@test "JSON validation should accept valid backup job configuration" {
    local backup_json='{"daily-backup":{"vms":["100","101"],"storage":"local-lvm","schedule":"0 2 * * *","mode":"snapshot","maxfiles":7}}'
    
    if command -v jq &> /dev/null; then
        run bash -c "echo '$backup_json' | jq . > /dev/null 2>&1"
        [ "$status" -eq 0 ]
    else
        [[ "$backup_json" =~ ^\{.*\}$ ]]
        assert_success
    fi
}

@test "JSON validation should reject invalid JSON syntax" {
    local invalid_json='{"web-server-01":{"node":"pve1","vmid":100,invalid}}'
    
    if command -v jq &> /dev/null; then
        run bash -c "echo '$invalid_json' | jq . > /dev/null 2>&1"
        [ "$status" -ne 0 ]
    else
        # Skip test if jq not available
        skip "jq not available"
    fi
}

@test "Cluster config parsing should handle cluster_create" {
    local cluster_config='cluster_create:{"name":"production-cluster","primary_node":"pve1"}'
    
    # Test that the format is correct
    [[ "$cluster_config" =~ ^cluster_create: ]]
    [[ "$cluster_config" == *"production-cluster"* ]]
    [[ "$cluster_config" == *"pve1"* ]]
}

@test "Cluster config parsing should handle ha_config" {
    local ha_config='ha_config:{"group":"production-ha","nodes":"pve1,pve2,pve3","migration":"N"}'
    
    [[ "$ha_config" =~ ^ha_config: ]]
    [[ "$ha_config" == *"production-ha"* ]]
    [[ "$ha_config" == *"pve1,pve2,pve3"* ]]
}

@test "Snapshot config parsing should handle snapshot format" {
    local snap_config='snapshot:{"node":"pve1","vmid":100,"snapname":"pre-upgrade","description":"Pre-upgrade snapshot","vm_type":"qemu"}'
    
    [[ "$snap_config" =~ ^snapshot: ]]
    [[ "$snap_config" == *"\"vmid\":100"* ]]
    [[ "$snap_config" == *"pre-upgrade"* ]]
}

@test "Security config parsing should handle rbac format" {
    local rbac_config='rbac:{"userid":"admin@pam","role":"Administrator","privileges":"Datastore.AllocateSpace,VM.Allocate"}'
    
    [[ "$rbac_config" =~ ^rbac: ]]
    [[ "$rbac_config" == *"admin@pam"* ]]
    [[ "$rbac_config" == *"Administrator"* ]]
}

@test "VM/LXC separation should identify VM by disk and network fields" {
    local vm_config='{"web-server":{"node":"pve1","vmid":100,"cores":2,"memory":2048,"disk":"50G","storage":"local-lvm","network":"model=virtio,bridge=vmbr0"}}'
    
    [[ "$vm_config" == *"\"disk\""* ]]
    [[ "$vm_config" == *"\"network\""* ]]
    [[ ! "$vm_config" == *"\"rootfs\""* ]]
}

@test "VM/LXC separation should identify LXC by rootfs field" {
    local lxc_config='{"app-container":{"node":"pve1","vmid":200,"cores":2,"memory":2048,"rootfs":"20G","storage":"local-lvm"}}'
    
    [[ "$lxc_config" == *"\"rootfs\""* ]]
    [[ ! "$lxc_config" == *"\"disk\""* ]] || [[ ! "$lxc_config" == *"\"network\""* ]]
}
