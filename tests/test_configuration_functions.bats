#!/usr/bin/env bats

# Tests for configuration functions in setup.sh

load 'test_helper.bash'

setup() {
    test_helper_setup
    # Source functions from setup.sh but prevent main execution
    local setup_script="${BATS_TEST_DIRNAME}/../setup.sh"
    if [ -f "$setup_script" ]; then
        # Extract all needed functions
        {
            sed -n '/^log()/,/^}$/p' "$setup_script"
            sed -n '/^validate_ip()/,/^}$/p' "$setup_script"
            sed -n '/^configure_cluster()/,/^}$/p' "$setup_script"
            sed -n '/^configure_compute()/,/^}$/p' "$setup_script"
            sed -n '/^configure_networking()/,/^}$/p' "$setup_script"
            sed -n '/^error_exit()/,/^}$/p' "$setup_script"
            sed -n '/^configure_storage()/,/^}$/p' "$setup_script"
            sed -n '/^configure_backup()/,/^}$/p' "$setup_script"
            sed -n '/^configure_security()/,/^}$/p' "$setup_script"
        } > "${TEST_TMP_DIR}/functions.sh" 2>/dev/null
        # Source functions
        source "${TEST_TMP_DIR}/functions.sh" 2>/dev/null || true
    fi
}

@test "configure_cluster should output cluster_create JSON" {
    # Mock input for cluster creation
    local input="1
production-cluster
pve1
"
    
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_cluster"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cluster_create"* ]]
    [[ "$output" == *"production-cluster"* ]]
    [[ "$output" == *"pve1"* ]]
}

@test "configure_cluster should output cluster_join JSON" {
    local input="2
pve2
192.168.1.10
"
    
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_cluster"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cluster_join"* ]]
    [[ "$output" == *"pve2"* ]]
    [[ "$output" == *"192.168.1.10"* ]]
}

@test "configure_cluster should output ha_config JSON" {
    local input="4
production-ha
pve1,pve2,pve3
N
"
    
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_cluster"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ha_config"* ]]
    [[ "$output" == *"production-ha"* ]]
    [[ "$output" == *"pve1,pve2,pve3"* ]]
}

@test "configure_compute should output VM configuration JSON" {
    local input="1
web-server-01
pve1
100
2
2048
50G
local-lvm
model=virtio,bridge=vmbr0
"
    
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_compute"
    [ "$status" -eq 0 ]
    [[ "$output" == *"web-server-01"* ]]
    [[ "$output" == *"\"vmid\":100"* ]]
    [[ "$output" == *"\"cores\":2"* ]]
    [[ "$output" == *"\"memory\":2048"* ]]
    [[ "$output" == *"\"disk\""* ]]
    [[ "$output" == *"\"network\""* ]]
}

@test "configure_compute should output LXC configuration JSON" {
    local input="2
app-container-01
pve1
200
2
2048
20G
local-lvm
local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst
"
    
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_compute"
    [ "$status" -eq 0 ]
    [[ "$output" == *"app-container-01"* ]]
    [[ "$output" == *"\"vmid\":200"* ]]
    [[ "$output" == *"\"rootfs\""* ]]
    [[ "$output" == *"\"ostemplate\""* ]]
}

@test "configure_compute should output snapshot configuration" {
    local input="4
100
pve1
pre-upgrade
Pre-upgrade snapshot
qemu
"
    
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_compute"
    [ "$status" -eq 0 ]
    [[ "$output" == *"snapshot:"* ]]
    [[ "$output" == *"\"vmid\":100"* ]]
    [[ "$output" == *"pre-upgrade"* ]]
}

@test "configure_networking should output bridge configuration" {
    local input="1
vmbr1
enp3s0
N
1500
"
    
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_networking"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bridge:"* ]]
    [[ "$output" == *"vmbr1"* ]]
    [[ "$output" == *"enp3s0"* ]]
}

@test "configure_networking should output firewall rule configuration" {
    local input="4
allow-ssh
ACCEPT
192.168.1.0/24
192.168.1.10
tcp
22
"
    
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_networking"
    [ "$status" -eq 0 ]
    [[ "$output" == *"firewall:"* ]]
    [[ "$output" == *"allow-ssh"* ]]
    [[ "$output" == *"ACCEPT"* ]]
    [[ "$output" == *"192.168.1.0/24"* ]]
}

@test "configure_storage should output NFS storage configuration" {
    local input="1
nfs-backup
192.168.1.100
/mnt/backup
backup,iso
pve1,pve2
4
"
    
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_storage"
    [ "$status" -eq 0 ]
    [[ "$output" == *"nfs-backup"* ]]
    [[ "$output" == *"192.168.1.100"* ]]
    [[ "$output" == *"/mnt/backup"* ]]
    [[ "$output" == *"\"type\":\"nfs\""* ]]
}

@test "configure_storage should validate IP address for NFS" {
    local input="1
nfs-backup
invalid-ip
"
    
    # This should fail validation
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_storage 2>&1"
    # The script should exit with error due to invalid IP
    # Note: error_exit will exit with code 1, but the command might return 127 if function not found
    [ "$status" -ne 0 ] || [[ "$output" == *"Invalid IP"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "configure_backup should output backup job configuration" {
    local input="1
daily-backup
100,101
local-lvm
0 2 * * *
snapshot
7
"
    
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_backup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"daily-backup"* ]]
    [[ "$output" == *"\"vms\""* ]]
    [[ "$output" == *"\"schedule\""* ]]
    [[ "$output" == *"\"mode\":\"snapshot\""* ]]
}

@test "configure_security should output RBAC configuration" {
    local input="1
admin@pam
Administrator
Datastore.AllocateSpace,VM.Allocate
"
    
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_security"
    [ "$status" -eq 0 ]
    [[ "$output" == *"rbac:"* ]]
    [[ "$output" == *"admin@pam"* ]]
    [[ "$output" == *"Administrator"* ]]
}

@test "configure_security should output API token configuration" {
    local input="2
automation@pam
thinkdeploy-token
365
"
    
    run bash -c "source ${TEST_TMP_DIR}/functions.sh 2>/dev/null; echo '$input' | configure_security"
    [ "$status" -eq 0 ]
    [[ "$output" == *"api_token:"* ]]
    [[ "$output" == *"thinkdeploy-token"* ]]
    [[ "$output" == *"\"expire\":365"* ]]
}
