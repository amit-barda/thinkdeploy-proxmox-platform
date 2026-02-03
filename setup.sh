#!/bin/bash

# ThinkDeploy Proxmox Automation Platform
# Senior Platform Engineer - Infrastructure Automation Architect
# Date: $(date +%Y-%m-%d)
# Purpose: Comprehensive Proxmox infrastructure management

set -euo pipefail

# Determine REPO_ROOT (absolute path) at script start - robust detection
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# If main.tf not in script directory, search upward
if [ ! -f "$REPO_ROOT/main.tf" ]; then
    search_dir="$REPO_ROOT"
    while [ "$search_dir" != "/" ]; do
        if [ -f "$search_dir/main.tf" ]; then
            REPO_ROOT="$search_dir"
            break
        fi
        search_dir="$(dirname "$search_dir")"
    done
fi
# Final validation - REPO_ROOT must exist and contain main.tf
if [ ! -f "$REPO_ROOT/main.tf" ]; then
    error_exit "Cannot find main.tf. REPO_ROOT=$REPO_ROOT is invalid. Please run setup.sh from the repository root."
fi
# Ensure REPO_ROOT is absolute
if [[ "$REPO_ROOT" != /* ]]; then
    REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
fi

# Configuration
SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/thinkdeploy-setup-$(date +%Y%m%d-%H%M%S).log"
VALIDATION_TIMEOUT="${VALIDATION_TIMEOUT:-20}"  # 20 seconds default

# Set persistent tfvars paths (absolute, based on REPO_ROOT)
GENERATED_DIR="$REPO_ROOT/generated"
TFVARS_FILE="$GENERATED_DIR/thinkdeploy.auto.tfvars.json"

# Redirect all output to log file AND screen
exec > >(tee -a "$LOG_FILE") 2>&1

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Warning function
warning() {
    log "WARNING: $1"
    echo "⚠️  $1" 1>&2
}

# Header
clear
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         ThinkDeploy Proxmox Automation Platform              ║"
echo "║         Enterprise Infrastructure Lifecycle Management        ║"
echo "║                    Version: $SCRIPT_VERSION                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

log "Starting ThinkDeploy infrastructure provisioning..."

# Prerequisites validation
log "Validating system prerequisites..."

if ! command -v terraform &> /dev/null; then
    error_exit "Terraform binary not found. Install from: https://terraform.io/downloads"
fi

# Check for Proxmox CLI tools (pvesh or proxmoxer)
PROXMOX_CLI_METHOD=""
if command -v pvesh &> /dev/null; then
    PROXMOX_CLI_METHOD="pvesh"
    log "Using pvesh CLI for Proxmox operations"
elif python3 -c "import proxmoxer" &> /dev/null; then
    PROXMOX_CLI_METHOD="proxmoxer"
    log "Using proxmoxer Python library for Proxmox operations"
else
    warning "Neither pvesh nor proxmoxer found. Some operations may fail."
    warning "Install: apt-get install proxmox-ve-cli OR pip install proxmoxer"
    PROXMOX_CLI_METHOD="none"
fi

# Check Terraform version
TF_VERSION=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || echo "unknown")
if [[ "$TF_VERSION" == "unknown" ]]; then
    log "WARNING: Could not determine Terraform version"
else
    log "Terraform version: $TF_VERSION"
fi

log "Prerequisites validation completed successfully"
echo ""

# Initialize terraform workspace
# Note: Terraform initialization will be done in run_terraform_deploy()
# This ensures init runs with latest modules before each deployment
log "Terraform workspace will be initialized during deployment orchestration"

# Validate configuration
log "Validating Terraform configuration..."
if terraform validate > /dev/null 2>&1; then
    log "Configuration validation passed"
else
    warning "Configuration validation had issues (this is OK if no resources configured yet)"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Infrastructure Configuration             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to get Proxmox connection details
configure_proxmox_connection() {
    echo "┌─ Proxmox Connection Configuration ────────────────────────┐" 1>&2
    echo "│ Configure connection to Proxmox cluster                    │" 1>&2
    echo "└─────────────────────────────────────────────────────────────┘" 1>&2
    echo "" 1>&2
    
    read -p "Proxmox API URL [https://localhost:8006/api2/json]: " pm_api_url
    pm_api_url=${pm_api_url:-https://localhost:8006/api2/json}
    
    read -p "Proxmox username [root@pam]: " pm_user
    pm_user=${pm_user:-root@pam}
    
    read -sp "Proxmox password: " pm_password
    echo ""
    [[ -z "$pm_password" ]] && error_exit "Password cannot be empty"
    
    read -p "Proxmox node hostname/IP for SSH [localhost]: " pm_ssh_host
    pm_ssh_host=${pm_ssh_host:-localhost}
    
    read -p "SSH user [root]: " pm_ssh_user
    pm_ssh_user=${pm_ssh_user:-root}
    
    read -p "SSH private key path [~/.ssh/id_rsa]: " pm_ssh_key
    pm_ssh_key=${pm_ssh_key:-~/.ssh/id_rsa}
    pm_ssh_key="${pm_ssh_key/#\~/$HOME}"
    # Expand to absolute path for Terraform (provisioners don't expand ~)
    pm_ssh_key=$(readlink -f "$pm_ssh_key" 2>/dev/null || realpath "$pm_ssh_key" 2>/dev/null || echo "$pm_ssh_key")
    [[ ! -f "$pm_ssh_key" ]] && error_exit "SSH key file not found: $pm_ssh_key"
    
    read -p "Skip TLS verification? (y/N) [N]: " tls_insecure
    tls_insecure=${tls_insecure:-N}
    pm_tls_insecure="false"
    if [[ "$tls_insecure" =~ ^[Yy]$ ]]; then
        pm_tls_insecure="true"
    fi
    
    # Export variables for terraform
    export TF_VAR_pm_api_url="$pm_api_url"
    export TF_VAR_pm_user="$pm_user"
    export TF_VAR_pm_password="$pm_password"
    export TF_VAR_pm_ssh_host="$pm_ssh_host"
    export TF_VAR_pm_ssh_user="$pm_ssh_user"
    export TF_VAR_pm_ssh_private_key_path="$pm_ssh_key"
    export TF_VAR_pm_tls_insecure="$pm_tls_insecure"
    
    log "Proxmox connection configured" 1>&2
}

# Validate Proxmox connection settings
validate_proxmox_connection() {
    local ssh_host="${TF_VAR_pm_ssh_host:-localhost}"
    local ssh_user="${TF_VAR_pm_ssh_user:-root}"
    local ssh_key="${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}"
    
    # Expand SSH key path
    ssh_key="${ssh_key/#\~/$HOME}"
    ssh_key=$(readlink -f "$ssh_key" 2>/dev/null || realpath "$ssh_key" 2>/dev/null || echo "$ssh_key")
    
    # Check if SSH key exists
    if [ ! -f "$ssh_key" ]; then
        error_exit "SSH key file not found: $ssh_key"
    fi
    
    # Validate localhost usage
    if [ "$ssh_host" = "localhost" ] || [ "$ssh_host" = "127.0.0.1" ]; then
        log "WARNING: pm_ssh_host is set to localhost. Validating we're on Proxmox host..."
        
        # Check if /etc/pve exists (Proxmox indicator)
        if [ ! -d "/etc/pve" ]; then
            # Try to run pvesh locally
            if ! command -v pvesh &> /dev/null; then
                error_exit "pm_ssh_host is 'localhost' but this doesn't appear to be a Proxmox host:" \
                    "  - /etc/pve directory not found" \
                    "  - pvesh command not found" \
                    "  Please set pm_ssh_host to the actual Proxmox node hostname/IP"
            fi
            
            # Try pvesh get /version
            if ! pvesh get /version &> /dev/null; then
                error_exit "pm_ssh_host is 'localhost' but pvesh cannot connect to Proxmox API." \
                    "  Please set pm_ssh_host to the actual Proxmox node hostname/IP"
            fi
        fi
        
        log "Confirmed: Running on Proxmox host (localhost validation passed)"
    fi
    
    # Validate SSH connectivity
    log "Testing SSH connectivity to ${ssh_user}@${ssh_host}..."
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$ssh_key" \
        "${ssh_user}@${ssh_host}" "echo 'SSH OK'" > /dev/null 2>&1; then
        error_exit "SSH connection to ${ssh_user}@${ssh_host} failed. Check SSH key and connectivity."
    fi
    log "SSH connectivity validated"
}

# Helper function to execute Proxmox commands using proxmoxer (Python API)
proxmoxer_execute() {
    local action=$1
    local resource=$2
    local params=$3
    
    if [ "$PROXMOX_CLI_METHOD" != "proxmoxer" ]; then
        return 1
    fi
    
    # Extract connection details from environment
    local api_url="${TF_VAR_pm_api_url:-https://localhost:8006/api2/json}"
    local user="${TF_VAR_pm_user:-root@pam}"
    local password="${TF_VAR_pm_password:-}"
    local verify_ssl="${TF_VAR_pm_tls_insecure:-false}"
    
    # Parse API URL to get host
    local host=$(echo "$api_url" | sed -E 's|https?://([^:/]+).*|\1|')
    
    # Create Python script to execute proxmoxer command
    python3 << EOF
import proxmoxer
import json
import sys

try:
    verify_ssl = ${verify_ssl} == "true"
    if verify_ssl:
        import urllib3
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    proxmox = proxmoxer.ProxmoxAPI(
        host='$host',
        user='$user',
        password='$password',
        verify_ssl=not verify_ssl
    )
    
    # Parse resource path (e.g., "/nodes/pve1/qemu" -> ["nodes", "pve1", "qemu"])
    resource_parts = [p for p in '$resource'.split('/') if p]
    
    # Navigate to resource
    current = proxmox
    for part in resource_parts:
        current = getattr(current, part)
    
    # Execute action
    if '$action' == 'get':
        result = current.get()
    elif '$action' == 'create':
        # Parse params (format: "key1=value1,key2=value2")
        params_dict = {}
        if '$params':
            for param in '$params'.split(','):
                if '=' in param:
                    key, value = param.split('=', 1)
                    params_dict[key.strip()] = value.strip()
        result = current.post(**params_dict)
    elif '$action' == 'set':
        params_dict = {}
        if '$params':
            for param in '$params'.split(','):
                if '=' in param:
                    key, value = param.split('=', 1)
                    params_dict[key.strip()] = value.strip()
        result = current.put(**params_dict)
    elif '$action' == 'delete':
        result = current.delete()
    else:
        print(f"Unknown action: $action", file=sys.stderr)
        sys.exit(1)
    
    print(json.dumps(result, indent=2))
    sys.exit(0)
except Exception as e:
    print(f"Error: {str(e)}", file=sys.stderr)
    sys.exit(1)
EOF
}

# Helper function to execute Proxmox commands (uses pvesh or proxmoxer)
proxmox_execute() {
    local method=$1
    local command=$2
    local args=$3
    
    if [ "$method" = "pvesh" ] && [ "$PROXMOX_CLI_METHOD" = "pvesh" ]; then
        # Use pvesh via SSH
        ssh -o StrictHostKeyChecking=no -i "${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}" \
            "${TF_VAR_pm_ssh_user:-root}@${TF_VAR_pm_ssh_host:-localhost}" \
            "pvesh $command $args" 2>&1
    elif [ "$method" = "proxmoxer" ] && [ "$PROXMOX_CLI_METHOD" = "proxmoxer" ]; then
        # Use proxmoxer Python API
        local action=$(echo "$command" | awk '{print $1}')
        local resource=$(echo "$command" | sed 's/^[^ ]* //' | awk '{print $1}')
        proxmoxer_execute "$action" "$resource" "$args"
    else
        log "WARNING: Proxmox CLI method not available"
        return 1
    fi
}

# Main menu function
show_main_menu() {
    # Display menu directly to terminal (stderr)
    clear >&2
    echo "" >&2
    echo "╔══════════════════════════════════════════════════════════════╗" >&2
    echo "║                    Main Configuration Menu                   ║" >&2
    echo "╚══════════════════════════════════════════════════════════════╝" >&2
    echo "" >&2
    echo "Available Options:" >&2
    echo "" >&2
    echo "  1. Cluster Management" >&2
    echo "     - Create cluster, Join nodes, HA, Corosync, Health checks" >&2
    echo "" >&2
    echo "  2. Compute / VM / LXC" >&2
    echo "     - Create VMs, LXC containers, Templates, Snapshots, Hotplug" >&2
    echo "" >&2
    echo "  3. Networking" >&2
    echo "     - Bridges, VLANs, SDN, Firewall rules, NAT, Bonding, MTU" >&2
    echo "" >&2
    echo "  4. Storage" >&2
    echo "     - NFS, iSCSI, Ceph, ZFS pools, Backup storage, Replication" >&2
    echo "" >&2
    echo "  5. Backup & DR" >&2
    echo "     - Backup jobs, Schedules, Verification, Restore, Offsite sync" >&2
    echo "" >&2
    echo "  6. Security" >&2
    echo "     - RBAC, API tokens, SSH hardening, Firewall policies, Audit" >&2
    echo "" >&2
    echo "  7. Deploy All" >&2
    echo "     - Deploy all configured resources" >&2
    echo "" >&2
    echo "  8. Exit" >&2
    echo "     - Exit without deploying" >&2
    echo "" >&2
    
    # Read from terminal (stdin) but prompt to stderr
    echo -n "Select option [8]: " >&2
    read main_option
    main_option=${main_option:-8}
    
    # Return option via stdout
    echo "$main_option"
}

# Cluster Management Menu
configure_cluster() {
    echo ""
    echo "┌─ Cluster Management ────────────────────────────────────────┐" 1>&2
    echo "│ Configure Proxmox cluster operations                        │" 1>&2
    echo "└─────────────────────────────────────────────────────────────┘" 1>&2
    echo "" 1>&2
    
    echo "Cluster Management Options:" 1>&2
    echo "1. Create cluster" 1>&2
    echo "2. Join node to cluster" 1>&2
    echo "3. Leave cluster (remove this node)" 1>&2
    echo "4. Configure HA (High Availability)" 1>&2
    echo "5. Tune Corosync" 1>&2
    echo "6. Health check" 1>&2
    echo "7. Backup cluster config" 1>&2
    echo "8. Back to main menu" 1>&2
    echo "" 1>&2
    
    read -p "Select option [8]: " cluster_option
    cluster_option=${cluster_option:-8}
    
    case "$cluster_option" in
        1)
            read -p "Cluster name [production-cluster]: " cluster_name
            cluster_name=${cluster_name:-production-cluster}
            read -p "Primary node [pve1]: " primary_node
            primary_node=${primary_node:-pve1}
            log "Cluster creation: $cluster_name on $primary_node"
            echo "cluster_create:{\"name\":\"$cluster_name\",\"primary_node\":\"$primary_node\"}"
            ;;
        2)
            read -p "Node to join [pve2]: " join_node
            join_node=${join_node:-pve2}
            read -p "Cluster IP address [192.168.1.10]: " cluster_ip
            cluster_ip=${cluster_ip:-192.168.1.10}
            log "Joining node: $join_node to cluster at $cluster_ip"
            echo "cluster_join:{\"node\":\"$join_node\",\"cluster_ip\":\"$cluster_ip\"}"
            ;;
        3)
            read -p "Node name to leave [$(hostname)]: " leave_node
            leave_node=${leave_node:-$(hostname)}
            read -p "Are you sure you want to leave the cluster? This will remove this node from the cluster. (y/N): " confirm_leave
            confirm_leave=${confirm_leave:-N}
            if [[ "$confirm_leave" =~ ^[Yy]$ ]]; then
                log "Leaving cluster: node $leave_node"
                echo "cluster_leave:{\"node\":\"$leave_node\",\"confirmed\":true}"
            else
                log "Cluster leave cancelled by user"
                echo ""
            fi
            ;;
        4)
            read -p "HA group name [production-ha]: " ha_group
            ha_group=${ha_group:-production-ha}
            read -p "HA nodes (comma-separated) [pve1,pve2,pve3]: " ha_nodes
            ha_nodes=${ha_nodes:-pve1,pve2,pve3}
            read -p "Migration enabled? (y/N) [N]: " ha_migration
            ha_migration=${ha_migration:-N}
            log "HA configuration: $ha_group"
            echo "ha_config:{\"group\":\"$ha_group\",\"nodes\":\"$ha_nodes\",\"migration\":\"$ha_migration\"}"
            ;;
        5)
            read -p "Token timeout (ms) [3000]: " token_timeout
            token_timeout=${token_timeout:-3000}
            read -p "Join timeout (ms) [20]: " join_timeout
            join_timeout=${join_timeout:-20}
            log "Corosync tuning: token=$token_timeout, join=$join_timeout"
            echo "corosync_tune:{\"token_timeout\":$token_timeout,\"join_timeout\":$join_timeout}"
            ;;
        6)
            log "Cluster health check requested"
            echo "health_check:{}"
            ;;
        7)
            read -p "Backup path [/backup/cluster-config]: " backup_path
            backup_path=${backup_path:-/backup/cluster-config}
            log "Cluster config backup: $backup_path"
            echo "cluster_backup:{\"path\":\"$backup_path\"}"
            ;;
        *)
            echo ""
            ;;
    esac
}

# VM/LXC Configuration
configure_compute() {
    echo ""
    echo "┌─ Compute / VM / LXC Management ───────────────────────────┐" 1>&2
    echo "│ Configure virtual machines and containers                  │" 1>&2
    echo "└─────────────────────────────────────────────────────────────┘" 1>&2
    echo "" 1>&2
    
    echo "Compute Options:" 1>&2
    echo "1. Create VM" 1>&2
    echo "2. Create LXC container" 1>&2
    echo "3. Create VM from template (cloud-init)" 1>&2
    echo "4. Create snapshot" 1>&2
    echo "5. Configure hotplug (CPU/RAM)" 1>&2
    echo "6. Configure auto-scaling" 1>&2
    echo "7. Add tags/labels" 1>&2
    echo "8. Back to main menu" 1>&2
    echo "" 1>&2
    
    read -p "Select option [8]: " compute_option
    compute_option=${compute_option:-8}
    
    case "$compute_option" in
        1)
            read -p "VM identifier [web-server-01]: " vm_id
            vm_id=${vm_id:-web-server-01}
            read -p "Proxmox node name [pve1]: " node
            node=${node:-pve1}
            read -p "VM ID number [100]: " vmid
            vmid=${vmid:-100}
            read -p "CPU cores [2]: " cores
            cores=${cores:-2}
            read -p "Memory (MB) [2048]: " memory
            memory=${memory:-2048}
            read -p "Disk size [50G]: " disk
            disk=${disk:-50G}
            read -p "Storage name [local-lvm]: " storage
            storage=${storage:-local-lvm}
            read -p "Network [model=virtio,bridge=vmbr0]: " network
            network=${network:-model=virtio,bridge=vmbr0}
            
            vm_config="\"$vm_id\":{\"node\":\"$node\",\"vmid\":$vmid,\"cores\":$cores,\"memory\":$memory,\"disk\":\"$disk\",\"storage\":\"$storage\",\"network\":\"$network\",\"enabled\":true}"
            log "VM configured: $vm_id (ID: $vmid)" 1>&2
            echo "$vm_config"
            ;;
        2)
            read -p "LXC identifier [app-container-01]: " lxc_id
            lxc_id=${lxc_id:-app-container-01}
            read -p "Node [pve1]: " node
            node=${node:-pve1}
            read -p "CT ID [200]: " ctid
            ctid=${ctid:-200}
            read -p "CPU cores [2]: " cores
            cores=${cores:-2}
            read -p "Memory (MB) [2048]: " memory
            memory=${memory:-2048}
            read -p "Root disk size [20G]: " rootfs
            rootfs=${rootfs:-20G}
            read -p "Storage [local-lvm]: " storage
            storage=${storage:-local-lvm}
            read -p "OS template [local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst]: " ostemplate
            ostemplate=${ostemplate:-local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst}
            
            lxc_config="\"$lxc_id\":{\"node\":\"$node\",\"vmid\":$ctid,\"cores\":$cores,\"memory\":$memory,\"rootfs\":\"$rootfs\",\"storage\":\"$storage\",\"ostemplate\":\"$ostemplate\",\"enabled\":true}"
            log "LXC configured: $lxc_id (ID: $ctid)" 1>&2
            echo "$lxc_config"
            ;;
        3)
            read -p "VM identifier [cloud-vm-01]: " vm_id
            vm_id=${vm_id:-cloud-vm-01}
            read -p "Node [pve1]: " node
            node=${node:-pve1}
            read -p "VM ID [101]: " vmid
            vmid=${vmid:-101}
            read -p "Template name [ubuntu-22.04-cloud]: " template
            template=${template:-ubuntu-22.04-cloud}
            read -p "Cloud-init user [admin]: " ci_user
            ci_user=${ci_user:-admin}
            read -p "SSH public key path [~/.ssh/id_rsa.pub]: " ssh_key
            ssh_key=${ssh_key:-~/.ssh/id_rsa.pub}
            ssh_key="${ssh_key/#\~/$HOME}"
            
            vm_config="\"$vm_id\":{\"node\":\"$node\",\"vmid\":$vmid,\"template\":\"$template\",\"cloud_init\":true,\"user\":\"$ci_user\",\"ssh_key\":\"$ssh_key\",\"enabled\":true}"
            log "VM with cloud-init configured: $vm_id" 1>&2
            echo "$vm_config"
            ;;
        4)
            # Get Proxmox connection details
            local pm_ssh_host="${TF_VAR_pm_ssh_host:-localhost}"
            local pm_ssh_user="${TF_VAR_pm_ssh_user:-root}"
            local pm_ssh_key="${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}"
            
            # Expand ~ to $HOME
            pm_ssh_key="${pm_ssh_key/#\~/$HOME}"
            pm_ssh_key="${pm_ssh_key//\$HOME/$HOME}"
            
            # Get node name
            read -p "Proxmox node name [local]: " node
            node=${node:-local}
            
            # Try to get list of VMs and LXCs from Proxmox
            echo "" 1>&2
            echo "Fetching list of VMs and LXC containers from node '$node'..." 1>&2
            local vm_list=""
            local lxc_list=""
            
            # Get VMs (qemu)
            set +e
            vm_list=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$pm_ssh_key" "$pm_ssh_user@$pm_ssh_host" \
                "pvesh get /nodes/$node/qemu --output-format json 2>/dev/null" 2>/dev/null | \
                jq -r '.[] | "\(.vmid) - \(.name // "unnamed") (qemu)"' 2>/dev/null || echo "")
            set -e
            
            # Get LXCs
            set +e
            lxc_list=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$pm_ssh_key" "$pm_ssh_user@$pm_ssh_host" \
                "pvesh get /nodes/$node/lxc --output-format json 2>/dev/null" 2>/dev/null | \
                jq -r '.[] | "\(.vmid) - \(.name // "unnamed") (lxc)"' 2>/dev/null || echo "")
            set -e
            
            # Display available VMs/LXCs
            if [ -n "$vm_list" ] || [ -n "$lxc_list" ]; then
                echo "" 1>&2
                echo "Available VMs and LXC containers on node '$node':" 1>&2
                echo "─────────────────────────────────────────────────" 1>&2
                local counter=1
                local vm_options=""
                
                if [ -n "$vm_list" ]; then
                    while IFS= read -r line; do
                        if [ -n "$line" ]; then
                            echo "$counter. $line" 1>&2
                            vm_options="$vm_options$counter|$line"$'\n'
                            counter=$((counter + 1))
                        fi
                    done <<< "$vm_list"
                fi
                
                if [ -n "$lxc_list" ]; then
                    while IFS= read -r line; do
                        if [ -n "$line" ]; then
                            echo "$counter. $line" 1>&2
                            vm_options="$vm_options$counter|$line"$'\n'
                            counter=$((counter + 1))
                        fi
                    done <<< "$lxc_list"
                fi
                
                echo "" 1>&2
                read -p "Select VM/LXC number [or enter VMID manually]: " selection
                
                # Parse selection
                local selected_vmid=""
                local selected_vm_type=""
                local selected_name=""
                
                if [[ "$selection" =~ ^[0-9]+$ ]]; then
                    # User selected from list
                    local selected_line
                    selected_line=$(echo "$vm_options" | grep "^$selection|" | cut -d'|' -f2-)
                    if [ -n "$selected_line" ]; then
                        selected_vmid=$(echo "$selected_line" | awk '{print $1}')
                        if [[ "$selected_line" == *"(lxc)"* ]]; then
                            selected_vm_type="lxc"
                        else
                            selected_vm_type="qemu"
                        fi
                        selected_name=$(echo "$selected_line" | sed 's/^[0-9]* - \(.*\) (.*)$/\1/')
                    else
                        echo "Invalid selection. Please enter VMID manually." 1>&2
                        read -p "VM ID: " selected_vmid
                        read -p "VM type (qemu/lxc) [qemu]: " selected_vm_type
                        selected_vm_type=${selected_vm_type:-qemu}
                    fi
                else
                    # User entered VMID manually
                    selected_vmid="$selection"
                    read -p "VM type (qemu/lxc) [qemu]: " selected_vm_type
                    selected_vm_type=${selected_vm_type:-qemu}
                fi
                
                vmid="$selected_vmid"
                vm_type="$selected_vm_type"
            else
                # Fallback to manual entry if we can't fetch list
                echo "Could not fetch VM/LXC list from Proxmox. Please enter manually." 1>&2
                read -p "VM ID to snapshot [100]: " vmid
                vmid=${vmid:-100}
                read -p "VM type (qemu/lxc) [qemu]: " vm_type
                vm_type=${vm_type:-qemu}
            fi
            
            # Get snapshot details
            read -p "Snapshot name [pre-upgrade]: " snap_name
            snap_name=${snap_name:-pre-upgrade}
            read -p "Description [Pre-upgrade snapshot]: " snap_desc
            snap_desc=${snap_desc:-Pre-upgrade snapshot}
            
            snap_config="{\"node\":\"$node\",\"vmid\":$vmid,\"snapname\":\"$snap_name\",\"description\":\"$snap_desc\",\"vm_type\":\"$vm_type\"}"
            log "Snapshot configured: $snap_name for $vm_type $vmid on node $node" 1>&2
            echo "snapshot:$snap_config"
            ;;
        5)
            read -p "VM ID [100]: " vmid
            vmid=${vmid:-100}
            read -p "Node [pve1]: " node
            node=${node:-pve1}
            read -p "Enable CPU hotplug? (y/N) [N]: " cpu_hotplug
            cpu_hotplug=${cpu_hotplug:-N}
            read -p "Enable RAM hotplug? (y/N) [N]: " ram_hotplug
            ram_hotplug=${ram_hotplug:-N}
            
            hotplug_config="{\"vmid\":$vmid,\"node\":\"$node\",\"cpu_hotplug\":\"$cpu_hotplug\",\"ram_hotplug\":\"$ram_hotplug\"}"
            log "Hotplug configured for VM $vmid" 1>&2
            echo "hotplug:$hotplug_config"
            ;;
        6)
            read -p "Auto-scaling group name [web-servers]: " as_group
            as_group=${as_group:-web-servers}
            read -p "Min VMs [2]: " min_vms
            min_vms=${min_vms:-2}
            read -p "Max VMs [10]: " max_vms
            max_vms=${max_vms:-10}
            read -p "Scale-up threshold (%) [80]: " scale_up
            scale_up=${scale_up:-80}
            read -p "Scale-down threshold (%) [30]: " scale_down
            scale_down=${scale_down:-30}
            
            as_config="{\"group\":\"$as_group\",\"min\":$min_vms,\"max\":$max_vms,\"scale_up\":$scale_up,\"scale_down\":$scale_down}"
            log "Auto-scaling configured: $as_group" 1>&2
            echo "autoscaling:$as_config"
            ;;
        7)
            read -p "VM ID [100]: " vmid
            vmid=${vmid:-100}
            read -p "Tags (comma-separated) [web,production]: " tags
            tags=${tags:-web,production}
            read -p "Labels (key=value, comma-separated) [env=prod,team=devops]: " labels
            labels=${labels:-env=prod,team=devops}
            
            tag_config="{\"vmid\":$vmid,\"tags\":\"$tags\",\"labels\":\"$labels\"}"
            log "Tags/labels configured for VM $vmid" 1>&2
            echo "tags:$tag_config"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Networking Configuration
configure_networking() {
    echo ""
    echo "┌─ Networking Management ───────────────────────────────────┐" 1>&2
    echo "│ Configure network infrastructure                           │" 1>&2
    echo "└─────────────────────────────────────────────────────────────┘" 1>&2
    echo "" 1>&2
    
    echo "Networking Options:" 1>&2
    echo "1. Create Linux bridge" 1>&2
    echo "2. Configure VLAN" 1>&2
    echo "3. Configure SDN" 1>&2
    echo "4. Firewall rules" 1>&2
    echo "5. NAT configuration" 1>&2
    echo "6. Network bonding" 1>&2
    echo "7. MTU optimization" 1>&2
    echo "8. Back to main menu" 1>&2
    echo "" 1>&2
    
    read -p "Select option [8]: " net_option
    net_option=${net_option:-8}
    
    case "$net_option" in
        1)
            read -p "Bridge name [vmbr1]: " bridge_name
            bridge_name=${bridge_name:-vmbr1}
            read -p "Physical interface [enp3s0]: " iface
            iface=${iface:-enp3s0}
            read -p "STP enabled? (y/N) [N]: " stp
            stp=${stp:-N}
            read -p "MTU [1500]: " mtu
            mtu=${mtu:-1500}
            
            bridge_config="\"$bridge_name\":{\"iface\":\"$iface\",\"stp\":\"$stp\",\"mtu\":$mtu}"
            log "Bridge configured: $bridge_name" 1>&2
            echo "bridge:$bridge_config"
            ;;
        2)
            read -p "VLAN ID [100]: " vlan_id
            vlan_id=${vlan_id:-100}
            read -p "VLAN name [management]: " vlan_name
            vlan_name=${vlan_name:-management}
            read -p "Bridge [vmbr0]: " bridge
            bridge=${bridge:-vmbr0}
            
            vlan_config="{\"id\":$vlan_id,\"name\":\"$vlan_name\",\"bridge\":\"$bridge\"}"
            log "VLAN configured: $vlan_id" 1>&2
            echo "vlan:$vlan_config"
            ;;
        4)
            read -p "Rule name [allow-ssh]: " rule_name
            rule_name=${rule_name:-allow-ssh}
            read -p "Action [ACCEPT]: " action
            action=${action:-ACCEPT}
            read -p "Source IP/CIDR [192.168.1.0/24]: " source
            source=${source:-192.168.1.0/24}
            read -p "Destination IP [192.168.1.10]: " dest
            dest=${dest:-192.168.1.10}
            read -p "Protocol [tcp]: " proto
            proto=${proto:-tcp}
            read -p "Destination port [22]: " dport
            dport=${dport:-22}
            
            fw_config="{\"name\":\"$rule_name\",\"action\":\"$action\",\"source\":\"$source\",\"dest\":\"$dest\",\"proto\":\"$proto\",\"dport\":$dport}"
            log "Firewall rule configured: $rule_name" 1>&2
            echo "firewall:$fw_config"
            ;;
        6)
            read -p "Bond name [bond0]: " bond_name
            bond_name=${bond_name:-bond0}
            read -p "Interfaces (comma-separated) [enp3s0,enp4s0]: " interfaces
            interfaces=${interfaces:-enp3s0,enp4s0}
            read -p "Bond mode [802.3ad]: " bond_mode
            bond_mode=${bond_mode:-802.3ad}
            
            bond_config="{\"name\":\"$bond_name\",\"interfaces\":\"$interfaces\",\"mode\":\"$bond_mode\"}"
            log "Bond configured: $bond_name" 1>&2
            echo "bond:$bond_config"
            ;;
        7)
            read -p "Interface name [vmbr1]: " iface
            iface=${iface:-vmbr1}
            read -p "MTU [9000]: " mtu
            mtu=${mtu:-9000}
            
            mtu_config="{\"interface\":\"$iface\",\"mtu\":$mtu}"
            log "MTU configured: $iface = $mtu" 1>&2
            echo "mtu:$mtu_config"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Storage Configuration
configure_storage() {
    echo ""
    echo "┌─ Storage Management ──────────────────────────────────────┐" 1>&2
    echo "│ Configure storage backends                                  │" 1>&2
    echo "└─────────────────────────────────────────────────────────────┘" 1>&2
    echo "" 1>&2
    
    echo "Storage Options:" 1>&2
    echo "1. NFS storage" 1>&2
    echo "2. iSCSI storage" 1>&2
    echo "3. Ceph storage" 1>&2
    echo "4. ZFS pool" 1>&2
    echo "5. Backup storage" 1>&2
    echo "6. Replication job" 1>&2
    echo "7. Storage encryption" 1>&2
    echo "8. Back to main menu" 1>&2
    echo "" 1>&2
    
    read -p "Select option [8]: " storage_option
    storage_option=${storage_option:-8}
    
    case "$storage_option" in
        1)
            read -p "Storage name [nfs-backup]: " storage_name
            storage_name=${storage_name:-nfs-backup}
            read -p "NFS server IP: " server_ip
            if ! validate_ip "$server_ip"; then
                error_exit "Invalid IP address format: $server_ip"
            fi
            read -p "NFS export path [/mnt/backup]: " export_path
            export_path=${export_path:-/mnt/backup}
            read -p "Content types (comma-separated) [backup,iso]: " content
            content=${content:-backup,iso}
            read -p "Nodes (comma-separated) [pve1,pve2]: " nodes
            nodes=${nodes:-pve1,pve2}
            read -p "NFS version [4]: " nfs_vers
            nfs_vers=${nfs_vers:-4}
            
            content_array=$(echo "$content" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
            nodes_array=$(echo "$nodes" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
            storage_config="\"$storage_name\":{\"type\":\"nfs\",\"server\":\"$server_ip\",\"export\":\"$export_path\",\"content\":[$content_array],\"nodes\":[$nodes_array],\"options\":{\"vers\":$nfs_vers}}"
            log "NFS storage configured: $storage_name" 1>&2
            echo "$storage_config"
            ;;
        2)
            read -p "Storage name [iscsi-storage]: " storage_name
            storage_name=${storage_name:-iscsi-storage}
            read -p "iSCSI server IP: " server_ip
            read -p "iSCSI target: " target
            read -p "Portal [3260]: " portal
            portal=${portal:-3260}
            read -p "Nodes (comma-separated) [pve1]: " nodes
            nodes=${nodes:-pve1}
            
            nodes_array=$(echo "$nodes" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
            storage_config="\"$storage_name\":{\"type\":\"iscsi\",\"server\":\"$server_ip\",\"target\":\"$target\",\"portal\":$portal,\"nodes\":[$nodes_array]}"
            log "iSCSI storage configured: $storage_name" 1>&2
            echo "$storage_config"
            ;;
        3)
            read -p "Storage name [ceph-pool]: " storage_name
            storage_name=${storage_name:-ceph-pool}
            read -p "Ceph pool name [proxmox]: " pool
            pool=${pool:-proxmox}
            read -p "Monitors (comma-separated IPs): " monitors
            read -p "Nodes (comma-separated) [pve1,pve2,pve3]: " nodes
            nodes=${nodes:-pve1,pve2,pve3}
            
            monitors_array=$(echo "$monitors" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
            nodes_array=$(echo "$nodes" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
            storage_config="\"$storage_name\":{\"type\":\"rbd\",\"pool\":\"$pool\",\"monhost\":[$monitors_array],\"nodes\":[$nodes_array]}"
            log "Ceph storage configured: $storage_name" 1>&2
            echo "$storage_config"
            ;;
        4)
            read -p "ZFS pool name [tank]: " pool_name
            pool_name=${pool_name:-tank}
            read -p "Disks (comma-separated) [sda,sdb]: " disks
            read -p "RAID level [mirror]: " raid_level
            raid_level=${raid_level:-mirror}
            
            zfs_config="{\"pool\":\"$pool_name\",\"disks\":\"$disks\",\"raid\":\"$raid_level\"}"
            log "ZFS pool configured: $pool_name" 1>&2
            echo "zfs:$zfs_config"
            ;;
        5)
            read -p "Backup storage name [backup-storage]: " storage_name
            storage_name=${storage_name:-backup-storage}
            read -p "Storage type [nfs]: " storage_type
            storage_type=${storage_type:-nfs}
            read -p "Retention days [30]: " retention
            retention=${retention:-30}
            
            backup_storage_config="\"$storage_name\":{\"type\":\"$storage_type\",\"retention_days\":$retention}"
            log "Backup storage configured: $storage_name" 1>&2
            echo "$backup_storage_config"
            ;;
        6)
            read -p "Replication job name [daily-replication]: " job_name
            job_name=${job_name:-daily-replication}
            read -p "Source storage [local-lvm]: " source_storage
            source_storage=${source_storage:-local-lvm}
            read -p "Target storage [backup-storage]: " target_storage
            target_storage=${target_storage:-backup-storage}
            read -p "Schedule [0 2 * * *]: " schedule
            schedule=${schedule:-0 2 * * *}
            
            repl_config="{\"name\":\"$job_name\",\"source\":\"$source_storage\",\"target\":\"$target_storage\",\"schedule\":\"$schedule\"}"
            log "Replication job configured: $job_name" 1>&2
            echo "replication:$repl_config"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Backup & DR Configuration
configure_backup() {
    echo ""
    echo "┌─ Backup & DR Management ───────────────────────────────────┐" 1>&2
    echo "│ Configure backup and disaster recovery                     │" 1>&2
    echo "└─────────────────────────────────────────────────────────────┘" 1>&2
    echo "" 1>&2
    
    echo "Backup Options:" 1>&2
    echo "1. Create backup job" 1>&2
    echo "2. Configure backup schedule" 1>&2
    echo "3. Backup verification" 1>&2
    echo "4. Restore testing" 1>&2
    echo "5. Offsite sync" 1>&2
    echo "6. Snapshot policy" 1>&2
    echo "7. DR workflow" 1>&2
    echo "8. Back to main menu" 1>&2
    echo "" 1>&2
    
    read -p "Select option [8]: " backup_option
    backup_option=${backup_option:-8}
    
    case "$backup_option" in
        1)
            read -p "Job identifier [daily-backup]: " job_id
            job_id=${job_id:-daily-backup}
            read -p "VM IDs to backup (comma-separated) [100]: " vm_ids
            vm_ids=${vm_ids:-100}
            read -p "Target storage [local-lvm]: " storage_name
            storage_name=${storage_name:-local-lvm}
            read -p "Cron schedule [0 2 * * *]: " schedule
            schedule=${schedule:-0 2 * * *}
            read -p "Backup mode [snapshot]: " mode
            mode=${mode:-snapshot}
            read -p "Max backup files [7]: " maxfiles
            maxfiles=${maxfiles:-7}
            
            vm_array=$(echo "$vm_ids" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
            job_config="\"$job_id\":{\"vms\":[$vm_array],\"storage\":\"$storage_name\",\"schedule\":\"$schedule\",\"mode\":\"$mode\",\"maxfiles\":$maxfiles}"
            log "Backup job configured: $job_id" 1>&2
            echo "$job_config"
            ;;
        3)
            read -p "Enable backup verification? (y/N) [N]: " verify
            verify=${verify:-N}
            read -p "Verification schedule [0 3 * * 0]: " verify_schedule
            verify_schedule=${verify_schedule:-0 3 * * 0}
            
            verify_config="{\"enabled\":\"$verify\",\"schedule\":\"$verify_schedule\"}"
            log "Backup verification configured" 1>&2
            echo "backup_verify:$verify_config"
            ;;
        4)
            read -p "Test restore schedule [0 4 * * 0]: " test_schedule
            test_schedule=${test_schedule:-0 4 * * 0}
            read -p "Test VMs (comma-separated IDs): " test_vms
            
            restore_test_config="{\"schedule\":\"$test_schedule\",\"test_vms\":\"$test_vms\"}"
            log "Restore testing configured" 1>&2
            echo "restore_test:$restore_test_config"
            ;;
        5)
            read -p "Offsite sync enabled? (y/N) [N]: " offsite_enabled
            offsite_enabled=${offsite_enabled:-N}
            read -p "Remote storage [s3://backup-bucket]: " remote_storage
            remote_storage=${remote_storage:-s3://backup-bucket}
            read -p "Sync schedule [0 3 * * *]: " sync_schedule
            sync_schedule=${sync_schedule:-0 3 * * *}
            
            offsite_config="{\"enabled\":\"$offsite_enabled\",\"remote\":\"$remote_storage\",\"schedule\":\"$sync_schedule\"}"
            log "Offsite sync configured" 1>&2
            echo "offsite_sync:$offsite_config"
            ;;
        6)
            read -p "Snapshot policy name [daily-snapshots]: " policy_name
            policy_name=${policy_name:-daily-snapshots}
            read -p "Keep daily [7]: " keep_daily
            keep_daily=${keep_daily:-7}
            read -p "Keep weekly [4]: " keep_weekly
            keep_weekly=${keep_weekly:-4}
            read -p "Keep monthly [12]: " keep_monthly
            keep_monthly=${keep_monthly:-12}
            
            snap_policy_config="{\"name\":\"$policy_name\",\"keep_daily\":$keep_daily,\"keep_weekly\":$keep_weekly,\"keep_monthly\":$keep_monthly}"
            log "Snapshot policy configured: $policy_name" 1>&2
            echo "snapshot_policy:$snap_policy_config"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Security Configuration
configure_security() {
    echo ""
    echo "┌─ Security Management ──────────────────────────────────────┐" 1>&2
    echo "│ Configure security policies                                │" 1>&2
    echo "└─────────────────────────────────────────────────────────────┘" 1>&2
    echo "" 1>&2
    
    echo "Security Options:" 1>&2
    echo "1. Configure RBAC" 1>&2
    echo "2. Create API token" 1>&2
    echo "3. SSH hardening" 1>&2
    echo "4. Firewall policies" 1>&2
    echo "5. Audit logging" 1>&2
    echo "6. Compliance profile" 1>&2
    echo "7. Back to main menu" 1>&2
    echo "" 1>&2
    
    read -p "Select option [7]: " security_option
    security_option=${security_option:-7}
    
    case "$security_option" in
        1)
            read -p "User ID [admin@pam]: " userid
            userid=${userid:-admin@pam}
            read -p "Role [Administrator]: " role
            role=${role:-Administrator}
            read -p "Privileges (comma-separated) [Datastore.AllocateSpace,VM.Allocate]: " privileges
            privileges=${privileges:-Datastore.AllocateSpace,VM.Allocate}
            
            rbac_config="{\"userid\":\"$userid\",\"role\":\"$role\",\"privileges\":\"$privileges\"}"
            log "RBAC configured: $userid" 1>&2
            echo "rbac:$rbac_config"
            ;;
        2)
            read -p "User ID [automation@pam]: " userid
            userid=${userid:-automation@pam}
            read -p "Token ID [thinkdeploy-token]: " tokenid
            tokenid=${tokenid:-thinkdeploy-token}
            read -p "Expire days [365]: " expire
            expire=${expire:-365}
            
            token_config="{\"userid\":\"$userid\",\"tokenid\":\"$tokenid\",\"expire\":$expire}"
            log "API token configured: $tokenid" 1>&2
            echo "api_token:$token_config"
            ;;
        3)
            read -p "Disable root login? (y/N) [y]: " no_root
            no_root=${no_root:-y}
            read -p "Disable password auth? (y/N) [y]: " no_password
            no_password=${no_password:-y}
            read -p "Max auth tries [3]: " max_tries
            max_tries=${max_tries:-3}
            
            ssh_config="{\"permit_root_login\":\"$no_root\",\"password_auth\":\"$no_password\",\"max_tries\":$max_tries}"
            log "SSH hardening configured" 1>&2
            echo "ssh_hardening:$ssh_config"
            ;;
        4)
            read -p "Firewall default policy [DROP]: " fw_policy
            fw_policy=${fw_policy:-DROP}
            read -p "Log level [info]: " log_level
            log_level=${log_level:-info}
            
            fw_policy_config="{\"default_policy\":\"$fw_policy\",\"log_level\":\"$log_level\"}"
            log "Firewall policy configured" 1>&2
            echo "firewall_policy:$fw_policy_config"
            ;;
        5)
            read -p "Enable audit logging? (y/N) [y]: " audit_enabled
            audit_enabled=${audit_enabled:-y}
            read -p "Retention days [90]: " retention
            retention=${retention:-90}
            
            audit_config="{\"enabled\":\"$audit_enabled\",\"retention_days\":$retention}"
            log "Audit logging configured" 1>&2
            echo "audit:$audit_config"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Main configuration workflow
log "Starting infrastructure configuration workflow..."

# Main loop
# Note: Proxmox connection variables should be set via environment variables or terraform.tfvars
# (pm_api_url, pm_user, pm_password, pm_ssh_host, pm_ssh_user, pm_ssh_private_key_path)

# Validate Proxmox connection before proceeding (if variables are set)
if [ -n "${TF_VAR_pm_ssh_host:-}" ] || [ -n "${TF_VAR_pm_ssh_user:-}" ] || [ -n "${TF_VAR_pm_ssh_private_key_path:-}" ]; then
    validate_proxmox_connection
fi

vms=""
lxcs=""
backup_jobs=""
storages=""
networking_configs=""
security_configs=""
cluster_configs=""
snapshots=""

echo ""
log "Entering main configuration menu..."

while true; do
    option=$(show_main_menu)
    
    case "$option" in
        1)
            result=$(configure_cluster)
            if [ -n "$result" ]; then
                if [ -z "$cluster_configs" ]; then
                    cluster_configs="$result"
                else
                    cluster_configs="$cluster_configs,$result"
                fi
                log "Cluster configuration added: ${result:0:50}..." 1>&2
            else
                log "No cluster configuration was added" 1>&2
            fi
            ;;
        2)
            result=$(configure_compute)
            if [ -n "$result" ]; then
                if [[ "$result" == *"snapshot:"* ]]; then
                    # Snapshot operation
                    if [ -z "$snapshots" ]; then
                        snapshots="$result"
                    else
                        snapshots="$snapshots,$result"
                    fi
                elif [[ "$result" == *"hotplug:"* ]] || [[ "$result" == *"autoscaling:"* ]] || [[ "$result" == *"tags:"* ]]; then
                    # Special compute operations (not VM/LXC resources)
                    if [ -z "$cluster_configs" ]; then
                        cluster_configs="$result"
                    else
                        cluster_configs="$cluster_configs,$result"
                    fi
                elif [[ "$result" == *"\"rootfs\""* ]]; then
                    # LXC container (has rootfs field, no disk/network)
                    if [ -z "$lxcs" ]; then
                        lxcs="$result"
                    else
                        lxcs="$lxcs,$result"
                    fi
                elif [[ "$result" == *"\"disk\""* ]] && [[ "$result" == *"\"network\""* ]]; then
                    # VM (has both disk and network fields)
                    if [ -z "$vms" ]; then
                        vms="$result"
                    else
                        vms="$vms,$result"
                    fi
                elif [[ "$result" == *"\"template\""* ]] || [[ "$result" == *"\"cloud_init\""* ]]; then
                    # VM with cloud-init (has template/cloud_init fields)
                    if [ -z "$vms" ]; then
                        vms="$result"
                    else
                        vms="$vms,$result"
                    fi
                else
                    # Default: assume VM if unclear (but log warning)
                    log "Warning: Could not determine if result is VM or LXC, assuming VM: ${result:0:50}..." 1>&2
                    if [ -z "$vms" ]; then
                        vms="$result"
                    else
                        vms="$vms,$result"
                    fi
                fi
            fi
            ;;
        3)
            result=$(configure_networking)
            if [ -n "$result" ]; then
                if [ -z "$networking_configs" ]; then
                    networking_configs="$result"
                else
                    networking_configs="$networking_configs,$result"
                fi
            fi
            ;;
        4)
            result=$(configure_storage)
            if [ -n "$result" ]; then
                if [ -z "$storages" ]; then
                    storages="$result"
                else
                    storages="$storages,$result"
                fi
            fi
            ;;
        5)
            result=$(configure_backup)
            if [ -n "$result" ]; then
                if [ -z "$backup_jobs" ]; then
                    backup_jobs="$result"
                else
                    backup_jobs="$backup_jobs,$result"
                fi
            fi
            ;;
        6)
            result=$(configure_security)
            if [ -n "$result" ]; then
                if [ -z "$security_configs" ]; then
                    security_configs="$result"
                else
                    security_configs="$security_configs,$result"
                fi
            fi
            ;;
        7)
            # Deploy All - set flag to deploy after tfvars is built
            DEPLOY_ALL_SELECTED=true
            break
            ;;
        8)
            log "Configuration cancelled by user"
            exit 0
            ;;
        *)
            log "Invalid option"
            ;;
    esac
done

# Build the terraform command
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Deployment Summary                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

log "Infrastructure configuration completed:"
if [ -n "$vms" ]; then
    # Count actual VMs from JSON (not commas)
    VM_COUNT=$(echo "{${vms}}" | jq 'keys | length' 2>/dev/null || echo "0")
    log "  - VMs: $VM_COUNT"
else
    log "  - VMs: 0"
fi
[ -n "$lxcs" ] && log "  - LXC containers: $(echo "$lxcs" | tr ',' '\n' | wc -l)"
[ -n "$backup_jobs" ] && log "  - Backup jobs: $(echo "$backup_jobs" | tr ',' '\n' | wc -l)"
[ -n "$storages" ] && log "  - Storage backends: $(echo "$storages" | tr ',' '\n' | wc -l)"
[ -n "$security_configs" ] && log "  - Security configs: $(echo "$security_configs" | tr ',' '\n' | wc -l)"
[ -n "$snapshots" ] && log "  - Snapshots: $(echo "$snapshots" | tr ',' '\n' | grep -c "snapshot:" || echo "0")"

# CRITICAL: If Deploy All was selected, skip all the old terraform_vars code and go straight to build_tfvars_file()
# This ensures Deploy All always works even if old code has issues
if [ "${DEPLOY_ALL_SELECTED:-false}" = "true" ]; then
    log "Deploy All selected - skipping old terraform_vars building, going straight to build_tfvars_file()"
    # Set a flag to skip the old code block
    SKIP_OLD_TERRAFORM_VARS=true
else
    SKIP_OLD_TERRAFORM_VARS=false
fi

# Build terraform command with -var flags (similar to old project style)
# NOTE: This is kept for backward compatibility but Deploy All uses build_tfvars_file() instead
# CRITICAL: If Deploy All is selected, skip all this old code to avoid errors blocking build_tfvars_file()
if [ "$SKIP_OLD_TERRAFORM_VARS" != "true" ]; then
    # Temporarily disable exit on error for this block to prevent it from stopping Deploy All
    set +e
    terraform_vars=""

if [ -n "$vms" ]; then
    terraform_vars="$terraform_vars -var='vms={${vms}}'"
else
    terraform_vars="$terraform_vars -var='vms={}'"
fi

if [ -n "$backup_jobs" ]; then
    terraform_vars="$terraform_vars -var='backup_jobs={${backup_jobs}}'"
else
    terraform_vars="$terraform_vars -var='backup_jobs={}'"
fi

if [ -n "$lxcs" ]; then
    terraform_vars="$terraform_vars -var='lxcs={${lxcs}}'"
else
    terraform_vars="$terraform_vars -var='lxcs={}'"
fi

if [ -n "$storages" ]; then
    terraform_vars="$terraform_vars -var='storages={${storages}}'"
else
    terraform_vars="$terraform_vars -var='storages={}'"
fi

if [ -n "$networking_configs" ]; then
    terraform_vars="$terraform_vars -var='networking_config={${networking_configs}}'"
else
    terraform_vars="$terraform_vars -var='networking_config={}'"
fi

if [ -n "$security_configs" ]; then
    # Parse security configs (rbac:{...},api_token:{...})
    # Convert format from "rbac:{...},api_token:{...}" to proper JSON structure
    SECURITY_JSON='{"api_tokens":{},"rbac":{}}'
    IFS=',' read -ra CONFIGS <<< "$security_configs"
    PARSING_ERRORS=0
    for config in "${CONFIGS[@]}"; do
        if [[ "$config" =~ ^rbac:(.+)$ ]]; then
            RBAC_DATA="${BASH_REMATCH[1]}"
            # Validate JSON syntax
            if ! echo "$RBAC_DATA" | jq . > /dev/null 2>&1; then
                warning "Invalid JSON in RBAC config: $RBAC_DATA"
                ((PARSING_ERRORS++))
                continue
            fi
            # Extract userid from rbac_data and use as key
            USERID=$(echo "$RBAC_DATA" | jq -r '.userid // empty' 2>/dev/null)
            if [ -z "$USERID" ] || [ "$USERID" = "null" ]; then
                warning "Missing userid in RBAC config"
                ((PARSING_ERRORS++))
                continue
            fi
            NEW_JSON=$(echo "$SECURITY_JSON" | jq ".rbac.\"$USERID\" = $RBAC_DATA" 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$NEW_JSON" ]; then
                SECURITY_JSON="$NEW_JSON"
                log "Added RBAC config for user: $USERID"
            else
                warning "Failed to add RBAC config for user: $USERID"
                ((PARSING_ERRORS++))
            fi
        elif [[ "$config" =~ ^api_token:(.+)$ ]]; then
            TOKEN_DATA="${BASH_REMATCH[1]}"
            # Validate JSON syntax
            if ! echo "$TOKEN_DATA" | jq . > /dev/null 2>&1; then
                warning "Invalid JSON in API token config: $TOKEN_DATA"
                ((PARSING_ERRORS++))
                continue
            fi
            # Extract tokenid from token_data and use as key
            TOKENID=$(echo "$TOKEN_DATA" | jq -r '.tokenid // empty' 2>/dev/null)
            if [ -z "$TOKENID" ] || [ "$TOKENID" = "null" ]; then
                warning "Missing tokenid in API token config"
                ((PARSING_ERRORS++))
                continue
            fi
            NEW_JSON=$(echo "$SECURITY_JSON" | jq ".api_tokens.\"$TOKENID\" = $TOKEN_DATA" 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$NEW_JSON" ]; then
                SECURITY_JSON="$NEW_JSON"
                log "Added API token config: $TOKENID"
            else
                warning "Failed to add API token config: $TOKENID"
                ((PARSING_ERRORS++))
            fi
        else
            warning "Unknown security config format: ${config:0:50}..."
            ((PARSING_ERRORS++))
        fi
    done
    
    if [ $PARSING_ERRORS -gt 0 ]; then
        warning "Security config parsing had $PARSING_ERRORS error(s), but continuing with valid configs"
    fi
    
    # Validate final JSON
    if ! echo "$SECURITY_JSON" | jq . > /dev/null 2>&1; then
        error_exit "Failed to build valid security_config JSON"
    fi
    
    # Escape JSON for shell (single quotes in terraform vars)
    SECURITY_JSON_ESCAPED=$(echo "$SECURITY_JSON" | sed "s/'/'\"'\"'/g")
    terraform_vars="$terraform_vars -var='security_config=$SECURITY_JSON_ESCAPED'"
else
    terraform_vars="$terraform_vars -var='security_config={}'"
fi

if [ -n "$snapshots" ]; then
    # Parse snapshots (snapshot:{...})
    # Convert format from "snapshot:{...}" to proper JSON structure
    SNAPSHOTS_JSON='{}'
    temp_snapshots="$snapshots"
    
    while [ -n "$temp_snapshots" ]; do
        if [[ "$temp_snapshots" =~ ^snapshot:(.+)$ ]]; then
            REST="${BASH_REMATCH[1]}"
            
            if [[ "$REST" =~ ^\{ ]]; then
                DEPTH=0
                VALUE=""
                for (( i=0; i<${#REST}; i++ )); do
                    CHAR="${REST:$i:1}"
                    VALUE="$VALUE$CHAR"
                    if [ "$CHAR" = "{" ]; then
                        ((DEPTH++))
                    elif [ "$CHAR" = "}" ]; then
                        ((DEPTH--))
                        if [ $DEPTH -eq 0 ]; then
                            break
                        fi
                    fi
                done
                
                temp_snapshots="${REST:${#VALUE}}"
                temp_snapshots="${temp_snapshots#*,}"
                
                # Parse snapshot config and create unique key
                if echo "$VALUE" | jq . > /dev/null 2>&1; then
                    VMID=$(echo "$VALUE" | jq -r '.vmid // ""' 2>/dev/null)
                    SNAPNAME=$(echo "$VALUE" | jq -r '.snapname // .name // ""' 2>/dev/null)
                    SNAPSHOT_KEY="snap-${VMID}-${SNAPNAME}"
                    # Ensure the JSON has the correct structure for Terraform
                    SNAPSHOT_OBJ=$(echo "$VALUE" | jq '{node: .node, vmid: .vmid, snapname: (.snapname // .name), description: (.description // ""), vm_type: (.vm_type // "qemu")}' 2>/dev/null || echo "$VALUE")
                    SNAPSHOTS_JSON=$(echo "$SNAPSHOTS_JSON" | jq ".\"$SNAPSHOT_KEY\" = $SNAPSHOT_OBJ" 2>/dev/null || echo "$SNAPSHOTS_JSON")
                fi
            else
                break
            fi
        else
            break
        fi
    done
    terraform_vars="$terraform_vars -var='snapshots=$SNAPSHOTS_JSON'"
else
    terraform_vars="$terraform_vars -var='snapshots={}'"
fi

# Function to detect actual Proxmox cluster status (source of truth)
# This queries Proxmox directly, not internal configs
# CRITICAL: This is the ONLY place that determines cluster existence
# Sets global variables: PROXMOX_CLUSTER_EXISTS, PROXMOX_CLUSTER_NAME, PROXMOX_CLUSTER_QUORATE, PROXMOX_CLUSTER_NODES
detect_proxmox_cluster() {
    # Initialize global variables (NOT local)
    PROXMOX_CLUSTER_EXISTS=false
    PROXMOX_CLUSTER_NAME=""
    PROXMOX_CLUSTER_QUORATE=""
    PROXMOX_CLUSTER_NODES=""
    
    # Check if we can query Proxmox
    # Try to detect cluster even if connection vars not set (use defaults)
    # This allows detection to work if vars are in environment or will be set later
    SSH_HOST="${TF_VAR_pm_ssh_host:-localhost}"
    SSH_USER="${TF_VAR_pm_ssh_user:-root}"
    SSH_KEY="${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}"
    
    if [ "$PROXMOX_CLI_METHOD" = "pvesh" ]; then
        # CRITICAL: Force JSON output - pvesh defaults to TABLE format
        # Query cluster status via pvesh with JSON output
        # Expand ~ in SSH key path
        SSH_KEY_EXPANDED="${SSH_KEY/#\~/$HOME}"
        CLUSTER_JSON=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -i "$SSH_KEY_EXPANDED" \
            "${SSH_USER}@${SSH_HOST}" \
            "pvesh get /cluster/status --output-format json 2>&1" 2>/dev/null)
        
        SSH_EXIT=$?
        
        if [ $SSH_EXIT -eq 0 ] && [ -n "$CLUSTER_JSON" ]; then
            # Parse JSON output using jq
            # /cluster/status can return either:
            # 1. Array format: [{"type":"cluster","name":"test-cluster",...}, {"type":"node",...}]
            # 2. Object format: {"name":"test-cluster","quorate":1,"nodes":1}
            
            # First, check if it's valid JSON
            if echo "$CLUSTER_JSON" | jq . > /dev/null 2>&1; then
                # Try array format first (Proxmox 8.x typical format)
                if echo "$CLUSTER_JSON" | jq -e 'type == "array" and (.[] | select(.type=="cluster"))' > /dev/null 2>&1; then
                    PROXMOX_CLUSTER_EXISTS=true
                    PROXMOX_CLUSTER_NAME=$(echo "$CLUSTER_JSON" | jq -r '.[] | select(.type=="cluster") | .name // empty' 2>/dev/null)
                    PROXMOX_CLUSTER_QUORATE=$(echo "$CLUSTER_JSON" | jq -r '.[] | select(.type=="cluster") | if .quorate == true or .quorate == 1 then "true" elif .quorate == false or .quorate == 0 then "false" else "unknown" end' 2>/dev/null)
                    PROXMOX_CLUSTER_NODES=$(echo "$CLUSTER_JSON" | jq '[.[] | select(.type=="node")] | length' 2>/dev/null)
                    
                # Try object format (alternative format)
                elif echo "$CLUSTER_JSON" | jq -e 'type == "object" and (.name != null or .quorate != null)' > /dev/null 2>&1; then
                    PROXMOX_CLUSTER_EXISTS=true
                    PROXMOX_CLUSTER_NAME=$(echo "$CLUSTER_JSON" | jq -r '.name // empty' 2>/dev/null)
                    PROXMOX_CLUSTER_QUORATE=$(echo "$CLUSTER_JSON" | jq -r 'if .quorate == true or .quorate == 1 then "true" elif .quorate == false or .quorate == 0 then "false" else "unknown" end' 2>/dev/null)
                    PROXMOX_CLUSTER_NODES=$(echo "$CLUSTER_JSON" | jq -r '.nodes // "unknown"' 2>/dev/null)
                    
                # Try array with direct cluster object (no type field)
                elif echo "$CLUSTER_JSON" | jq -e 'type == "array" and (.[] | .name != null)' > /dev/null 2>&1; then
                    # First entry might be cluster info
                    PROXMOX_CLUSTER_EXISTS=true
                    PROXMOX_CLUSTER_NAME=$(echo "$CLUSTER_JSON" | jq -r '.[0].name // empty' 2>/dev/null)
                    PROXMOX_CLUSTER_QUORATE=$(echo "$CLUSTER_JSON" | jq -r 'if .[0].quorate == true or .[0].quorate == 1 then "true" elif .[0].quorate == false or .[0].quorate == 0 then "false" else "unknown" end' 2>/dev/null)
                    PROXMOX_CLUSTER_NODES=$(echo "$CLUSTER_JSON" | jq -r '.[0].nodes // "unknown"' 2>/dev/null)
                fi
            fi
            
            # If still no cluster found, try pvecm fallback
            if [ "$PROXMOX_CLUSTER_EXISTS" != "true" ]; then
                # Try alternative method: pvecm status (for older Proxmox or different output format)
                PVECM_STATUS=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
                    -i "$SSH_KEY_EXPANDED" \
                    "${SSH_USER}@${SSH_HOST}" \
                    "pvecm status 2>&1" 2>/dev/null)
                
                if [ $? -eq 0 ] && echo "$PVECM_STATUS" | grep -q "Cluster information\|Cluster name" > /dev/null 2>&1; then
                    PROXMOX_CLUSTER_EXISTS=true
                    PROXMOX_CLUSTER_NAME=$(echo "$PVECM_STATUS" | grep -i "Cluster name" | sed -E 's/.*Cluster name[[:space:]]*:[[:space:]]*([^[:space:]]+).*/\1/i' | head -1)
                    [ -z "$PROXMOX_CLUSTER_NAME" ] && PROXMOX_CLUSTER_NAME="unknown"
                    PROXMOX_CLUSTER_QUORATE="unknown"
                    PROXMOX_CLUSTER_NODES="unknown"
                fi
            fi
        else
            # SSH or pvesh command failed - try pvecm as fallback
            PVECM_STATUS=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
                -i "$SSH_KEY_EXPANDED" \
                "${SSH_USER}@${SSH_HOST}" \
                "pvecm status 2>&1" 2>/dev/null)
            
            if [ $? -eq 0 ] && echo "$PVECM_STATUS" | grep -q "Cluster information\|Cluster name" > /dev/null 2>&1; then
                PROXMOX_CLUSTER_EXISTS=true
                PROXMOX_CLUSTER_NAME=$(echo "$PVECM_STATUS" | grep -i "Cluster name" | sed -E 's/.*Cluster name[[:space:]]*:[[:space:]]*([^[:space:]]+).*/\1/i' | head -1)
                [ -z "$PROXMOX_CLUSTER_NAME" ] && PROXMOX_CLUSTER_NAME="unknown"
                PROXMOX_CLUSTER_QUORATE="unknown"
                PROXMOX_CLUSTER_NODES="unknown"
            fi
        fi
    fi
    
    # Validate and set defaults
    [ -z "$PROXMOX_CLUSTER_NAME" ] && PROXMOX_CLUSTER_NAME=""
    [ -z "$PROXMOX_CLUSTER_QUORATE" ] && PROXMOX_CLUSTER_QUORATE=""
    [ -z "$PROXMOX_CLUSTER_NODES" ] && PROXMOX_CLUSTER_NODES=""
}

# Detect actual Proxmox cluster FIRST (before checking internal configs)
# This is the source of truth - Proxmox cluster existence is independent of tool's internal config
# CRITICAL: This runs ONCE and sets global variables
detect_proxmox_cluster

# Make variables readonly to prevent accidental override
readonly PROXMOX_CLUSTER_EXISTS
readonly PROXMOX_CLUSTER_NAME
readonly PROXMOX_CLUSTER_QUORATE
readonly PROXMOX_CLUSTER_NODES

# EXACTLY ONE place that logs cluster detection result
if [ "$PROXMOX_CLUSTER_EXISTS" = "true" ]; then
    log "Existing Proxmox cluster detected: $PROXMOX_CLUSTER_NAME (external / unmanaged by ThinkDeploy)"
else
    log "No Proxmox cluster detected (standalone node)"
fi

if [ -n "$cluster_configs" ]; then
    # Parse cluster_configs (cluster_create:{...},ha_config:{...},autoscaling:{...})
    # Convert format from "key:value,key:value" to proper JSON structure matching Terraform variable
    # The Terraform variable expects: {create_cluster, cluster_name, primary_node, join_node, ha_enabled, ha_group_name, ha_nodes}
    # IMPORTANT: cluster_configs indicates "managed by this tool", not "exists in Proxmox"
    CLUSTER_JSON='{"create_cluster":false,"cluster_name":"","primary_node":"","join_node":"","ha_enabled":false,"ha_group_name":"","ha_nodes":[]}'
    AUTOSCALING_JSON=""  # Initialize autoscaling JSON (will be set if autoscaling config is found)
    temp_configs="$cluster_configs"
    log "Starting cluster parsing loop with temp_configs: $temp_configs" 1>&2
    
    # Match patterns like "key:{...}" where {...} can contain commas and nested braces
    # Handle multiple entries separated by commas
    LOOP_COUNT=0
    MAX_LOOPS=100  # Prevent infinite loops
    PREV_LENGTH=0
    
    while [ -n "$temp_configs" ] && [ $LOOP_COUNT -lt $MAX_LOOPS ]; do
        ((LOOP_COUNT++))
        
        # Trim leading whitespace and commas
        temp_configs=$(echo "$temp_configs" | sed 's/^[[:space:],]*//')
        
        # Check if we're stuck (same length as before)
        CURRENT_LENGTH=${#temp_configs}
        if [ $CURRENT_LENGTH -eq $PREV_LENGTH ] && [ $CURRENT_LENGTH -gt 0 ]; then
            warning "Cluster parsing loop detected - breaking to prevent infinite loop"
            log "Remaining unparsed config: $temp_configs" 1>&2
            break
        fi
        PREV_LENGTH=$CURRENT_LENGTH
        
        if [[ "$temp_configs" =~ ^([^:]+):(.+)$ ]]; then
            KEY="${BASH_REMATCH[1]}"
            REST="${BASH_REMATCH[2]}"
            
            if [[ "$REST" =~ ^\{ ]]; then
                DEPTH=0
                VALUE=""
                for (( i=0; i<${#REST}; i++ )); do
                    CHAR="${REST:$i:1}"
                    VALUE="$VALUE$CHAR"
                    if [ "$CHAR" = "{" ]; then
                        ((DEPTH++))
                    elif [ "$CHAR" = "}" ]; then
                        ((DEPTH--))
                        if [ $DEPTH -eq 0 ]; then
                            break
                        fi
                    fi
                done
                
                # Remove the parsed value from temp_configs
                REMAINING="${REST:${#VALUE}}"
                # Remove leading comma and any whitespace
                temp_configs=$(echo "$REMAINING" | sed 's/^[[:space:],]*//')
                
                # Parse the value and map to Terraform variable structure
                if echo "$VALUE" | jq . > /dev/null 2>&1; then
                    log "Parsing cluster config: KEY=$KEY, VALUE=$VALUE" 1>&2
                    case "$KEY" in
                        cluster_create)
                            # Only process if create_cluster is not already set to true
                            CURRENT_CREATE=$(echo "$CLUSTER_JSON" | jq -r '.create_cluster // false' 2>/dev/null)
                            if [ "$CURRENT_CREATE" != "true" ]; then
                                CLUSTER_NAME=$(echo "$VALUE" | jq -r '.name // ""' 2>/dev/null)
                                PRIMARY_NODE=$(echo "$VALUE" | jq -r '.primary_node // ""' 2>/dev/null)
                                log "Extracted: cluster_name=$CLUSTER_NAME, primary_node=$PRIMARY_NODE" 1>&2
                                if [ -n "$CLUSTER_NAME" ] && [ -n "$PRIMARY_NODE" ]; then
                                    # CRITICAL: Use Proxmox as source of truth - if cluster exists in Proxmox, NEVER try to create it
                                    # This prevents attempting to create a cluster that already exists (brownfield scenario)
                                    if [ "$PROXMOX_CLUSTER_EXISTS" = "true" ]; then
                                        log "Proxmox cluster already exists ($PROXMOX_CLUSTER_NAME) - setting create_cluster=false (safe: will not attempt creation)" 1>&2
                                        # Use actual Proxmox cluster name if available, otherwise use configured name
                                        FINAL_CLUSTER_NAME="${PROXMOX_CLUSTER_NAME:-$CLUSTER_NAME}"
                                        CLUSTER_JSON=$(echo "$CLUSTER_JSON" | jq ".create_cluster = false | .cluster_name = \"$FINAL_CLUSTER_NAME\" | .primary_node = \"$PRIMARY_NODE\"" 2>/dev/null || echo "$CLUSTER_JSON")
                                    else
                                        log "No existing Proxmox cluster detected - setting create_cluster=true (will create new cluster)" 1>&2
                                        CLUSTER_JSON=$(echo "$CLUSTER_JSON" | jq ".create_cluster = true | .cluster_name = \"$CLUSTER_NAME\" | .primary_node = \"$PRIMARY_NODE\"" 2>/dev/null || echo "$CLUSTER_JSON")
                                    fi
                                    
                                    JQ_EXIT=$?
                                    if [ $JQ_EXIT -ne 0 ]; then
                                        log "ERROR: Failed to update CLUSTER_JSON with jq (exit code: $JQ_EXIT)" 1>&2
                                    else
                                        log "Successfully updated CLUSTER_JSON (create_cluster=$([ "$CLUSTER_EXISTS" = "yes" ] && echo "false" || echo "true"))" 1>&2
                                    fi
                                else
                                    log "WARNING: cluster_name or primary_node is empty, skipping" 1>&2
                                fi
                            else
                                log "Cluster creation already configured, skipping duplicate" 1>&2
                            fi
                            ;;
                        cluster_join)
                            JOIN_NODE=$(echo "$VALUE" | jq -r '.node // ""' 2>/dev/null)
                            CLUSTER_IP=$(echo "$VALUE" | jq -r '.cluster_ip // ""' 2>/dev/null)
                            if [ -n "$JOIN_NODE" ]; then
                                NEW_JSON=$(echo "$CLUSTER_JSON" | jq ".join_node = \"$JOIN_NODE\"" 2>/dev/null)
                                if [ $? -eq 0 ] && [ -n "$NEW_JSON" ]; then
                                    CLUSTER_JSON="$NEW_JSON"
                                    log "Set join_node: $JOIN_NODE"
                                fi
                            fi
                            ;;
                        ha_config)
                            HA_GROUP=$(echo "$VALUE" | jq -r '.group // ""' 2>/dev/null)
                            HA_NODES_STR=$(echo "$VALUE" | jq -r '.nodes // ""' 2>/dev/null)
                            # Convert comma-separated string to JSON array
                            if [ -n "$HA_NODES_STR" ]; then
                                HA_NODES_JSON=$(echo "$HA_NODES_STR" | tr ',' '\n' | jq -R . | jq -s . 2>/dev/null || echo "[]")
                                NEW_JSON=$(echo "$CLUSTER_JSON" | jq ".ha_enabled = true | .ha_group_name = \"$HA_GROUP\" | .ha_nodes = $HA_NODES_JSON" 2>/dev/null)
                                if [ $? -eq 0 ] && [ -n "$NEW_JSON" ]; then
                                    CLUSTER_JSON="$NEW_JSON"
                                    log "Set HA config: group=$HA_GROUP, nodes=$HA_NODES_STR"
                                fi
                            fi
                            ;;
                        autoscaling)
                            # Extract autoscaling configuration
                            AS_GROUP=$(echo "$VALUE" | jq -r '.group // ""' 2>/dev/null)
                            AS_MIN=$(echo "$VALUE" | jq -r '.min // 2' 2>/dev/null)
                            AS_MAX=$(echo "$VALUE" | jq -r '.max // 10' 2>/dev/null)
                            AS_SCALE_UP=$(echo "$VALUE" | jq -r '.scale_up // 80' 2>/dev/null)
                            AS_SCALE_DOWN=$(echo "$VALUE" | jq -r '.scale_down // 30' 2>/dev/null)
                            if [ -n "$AS_GROUP" ]; then
                                # Build autoscaling JSON
                                AUTOSCALING_JSON=$(jq -n \
                                    --arg group "$AS_GROUP" \
                                    --argjson min "$AS_MIN" \
                                    --argjson max "$AS_MAX" \
                                    --argjson scale_up "$AS_SCALE_UP" \
                                    --argjson scale_down "$AS_SCALE_DOWN" \
                                    '{
                                        group: $group,
                                        min: $min,
                                        max: $max,
                                        scale_up: $scale_up,
                                        scale_down: $scale_down
                                    }' 2>/dev/null)
                                if [ $? -eq 0 ] && [ -n "$AUTOSCALING_JSON" ]; then
                                    log "Processed autoscaling config: group=$AS_GROUP, min=$AS_MIN, max=$AS_MAX, scale_up=$AS_SCALE_UP, scale_down=$AS_SCALE_DOWN"
                                else
                                    warning "Failed to build autoscaling JSON"
                                fi
                            else
                                warning "Autoscaling group name is empty, skipping"
                            fi
                            ;;
                        *)
                            log "WARNING: Unknown cluster config key: $KEY" 1>&2
                            ;;
                    esac
                else
                    log "WARNING: Invalid JSON in cluster config: $VALUE" 1>&2
                    # Break if we can't parse - avoid infinite loop
                    break
                fi
            else
                # No opening brace found, break
                break
            fi
        else
            # No pattern match, break
            break
        fi
    done
    
    if [ $LOOP_COUNT -ge $MAX_LOOPS ]; then
        warning "Cluster parsing loop reached maximum iterations ($MAX_LOOPS)"
    fi
    
    # Validate final JSON
    if ! echo "$CLUSTER_JSON" | jq . > /dev/null 2>&1; then
        error_exit "Failed to build valid cluster_config JSON"
    fi
    
    log "Final cluster_config JSON: $CLUSTER_JSON" 1>&2
    # Escape JSON for shell
    CLUSTER_JSON_ESCAPED=$(echo "$CLUSTER_JSON" | sed "s/'/'\"'\"'/g")
    terraform_vars="$terraform_vars -var='cluster_config=$CLUSTER_JSON_ESCAPED'"
else
    # No internal cluster_configs found - but check if Proxmox cluster exists
    # These are separate concepts:
    # - cluster_configs = "managed by this tool" (internal JSON)
    # - Proxmox cluster = "exists in Proxmox" (actual infrastructure)
    # NOTE: Cluster detection already logged above - don't duplicate
    if [ "$PROXMOX_CLUSTER_EXISTS" = "true" ]; then
        echo "ℹ️  Proxmox cluster exists but is not managed by this tool. You can still configure:" 1>&2
        echo "   - HA groups" 1>&2
        echo "   - Join additional nodes" 1>&2
        echo "   - VMs, storage, networking, security" 1>&2
        # Set cluster info but with create_cluster=false (safe: won't try to create)
        CLUSTER_JSON="{\"create_cluster\":false,\"cluster_name\":\"$PROXMOX_CLUSTER_NAME\",\"primary_node\":\"\",\"join_node\":\"\",\"ha_enabled\":false,\"ha_group_name\":\"\",\"ha_nodes\":[]}"
        CLUSTER_JSON_ESCAPED=$(echo "$CLUSTER_JSON" | sed "s/'/'\"'\"'/g")
        terraform_vars="$terraform_vars -var='cluster_config=$CLUSTER_JSON_ESCAPED'"
    else
        terraform_vars="$terraform_vars -var='cluster_config={}'"
    fi
fi
    # Re-enable exit on error
    set -e
fi

# Build terraform variables JSON file (safer than command-line args)
# This will be used for both plan and apply
# Use persistent location inside repo: ./generated/thinkdeploy.auto.tfvars.json
# Note: REPO_ROOT, GENERATED_DIR, and TFVARS_FILE are set at script start (absolute paths)

# Function to run complete Terraform deployment
# Uses subshell (cd) instead of -chdir for maximum compatibility
# CRITICAL: This function must be defined BEFORE build_tfvars_file() because
# build_tfvars_file() calls it when Deploy All is selected
run_terraform_deploy() {
    local tfvars_file="$1"
    
    # Use REPO_ROOT as TF_ROOT (already set at script start)
    local TF_ROOT="$REPO_ROOT"
    
    # Ensure GENERATED_DIR exists for plan file
    mkdir -p "$GENERATED_DIR" || error_exit "Failed to create generated directory: $GENERATED_DIR"
    local PLAN_FILE="$GENERATED_DIR/thinkdeploy.plan"
    
    # Convert tfvars_file to absolute path if relative
    if [[ "$tfvars_file" != /* ]]; then
        tfvars_file="$(cd "$(dirname "$tfvars_file")" && pwd)/$(basename "$tfvars_file")"
    fi
    
    # Guards - fail fast
    [ -f "$tfvars_file" ] || error_exit "tfvars not found: $tfvars_file (absolute path: $tfvars_file)"
    jq -e . "$tfvars_file" >/dev/null 2>&1 || error_exit "tfvars invalid json: $tfvars_file"
    [ -n "${TF_ROOT:-}" ] || error_exit "TF_ROOT is empty"
    [ -f "$TF_ROOT/main.tf" ] || error_exit "main.tf not found in TF_ROOT=$TF_ROOT"
    
    log "=== RUN_TERRAFORM_DEPLOY START ==="
    
    # SAFETY GUARD: Prevent accidental destroy when vars are empty
    log "Running safety checks before deployment..."
    
    # Get state list first (needed for safety checks)
    local state_list_output=""
    if [ -f "$TF_ROOT/.terraform/terraform.tfstate" ] || [ -f "$TF_ROOT/terraform.tfstate" ]; then
        set +e  # Temporarily disable exit on error
        state_list_output=$(terraform -chdir="$TF_ROOT" state list 2>/dev/null || echo "")
        set -e  # Re-enable exit on error
    fi
    
    # Check if state has module.vm resources but tfvars has empty vms
    local state_has_vms=false
    local tfvars_has_vms=false
    
    if [ -n "$state_list_output" ]; then
        # Check state for module.vm resources
        if echo "$state_list_output" | grep -q "^module\.vm\["; then
            state_has_vms=true
            log "State contains module.vm resources"
        fi
        
        # Check tfvars for vms
        local vms_count
        vms_count=$(jq -r '.vms // {} | keys | length' "$tfvars_file" 2>/dev/null || echo "0")
        if [ "$vms_count" -gt 0 ]; then
            tfvars_has_vms=true
            log "Tfvars contains $vms_count VM(s)"
        else
            log "Tfvars has 0 VMs (vms: {})"
        fi
        
        # Safety check: Compare state VMs with tfvars VMs to detect VMs that will be destroyed
        # This prevents accidental destruction when running with different configurations
        if [ "$state_has_vms" = "true" ]; then
            # Get list of VMs in state
            local state_vm_list
            state_vm_list=$(echo "$state_list_output" | grep "^module\.vm\[" | sed 's/^module\.vm\["\(.*\)"\]\.null_resource\.vm\[0\]$/\1/' || echo "")
            
            # Get list of VMs in tfvars
            local tfvars_vm_list
            tfvars_vm_list=$(jq -r '.vms // {} | keys[]' "$tfvars_file" 2>/dev/null || echo "")
            
            log "DEBUG Safety Guard: State VMs: $state_vm_list, Tfvars VMs: $tfvars_vm_list"
            
            # Find VMs in state that are NOT in tfvars OR have changed VMID (these will be destroyed)
            local vms_to_destroy=""
            # Handle case where state_vm_list or tfvars_vm_list might be empty
            if [ -n "$state_vm_list" ]; then
                for state_vm in $state_vm_list; do
                    local vm_found=false
                    local vm_vmid_changed=false
                    # Get VMID from state (need to query terraform state for this VM's vmid from triggers)
                    local state_vmid=""
                    set +e  # Temporarily disable exit on error
                    state_vmid=$(terraform -chdir="$TF_ROOT" state show "module.vm[\"$state_vm\"].null_resource.vm[0]" 2>/dev/null | grep -E '^\s+"vmid"\s+=' | awk '{print $3}' | tr -d '"' || echo "")
                    set -e  # Re-enable exit on error
                    
                    # Check if this VM exists in tfvars
                    if [ -n "$tfvars_vm_list" ]; then
                        for tfvars_vm in $tfvars_vm_list; do
                            if [ "$state_vm" = "$tfvars_vm" ]; then
                                vm_found=true
                                # Check if VMID changed (this would cause destruction)
                                local tfvars_vmid
                                tfvars_vmid=$(jq -r ".vms[\"$tfvars_vm\"].vmid" "$tfvars_file" 2>/dev/null || echo "")
                                if [ -n "$state_vmid" ] && [ -n "$tfvars_vmid" ] && [ "$state_vmid" != "$tfvars_vmid" ]; then
                                    vm_vmid_changed=true
                                    log "DEBUG Safety Guard: VM '$state_vm' found in both state and tfvars, but VMID changed: state=$state_vmid, tfvars=$tfvars_vmid - will be destroyed"
                                fi
                                break
                            fi
                        done
                    fi
                    if [ "$vm_found" = "false" ] || [ "$vm_vmid_changed" = "true" ]; then
                        if [ -z "$vms_to_destroy" ]; then
                            vms_to_destroy="$state_vm"
                        else
                            vms_to_destroy="$vms_to_destroy, $state_vm"
                        fi
                        if [ "$vm_found" = "false" ]; then
                            log "DEBUG Safety Guard: VM '$state_vm' found in state but NOT in tfvars - will be destroyed"
                        fi
                    fi
                done
            fi
            
            # If there are VMs that will be destroyed, warn the user
            # Explicitly check if variable is non-empty (handle whitespace/empty string edge cases)
            if [ -n "$vms_to_destroy" ] && [ "$vms_to_destroy" != "" ]; then
                log "SAFETY GUARD: Detected VMs that will be destroyed: $vms_to_destroy"
                if [ "${THINKDEPLOY_ALLOW_DESTROY:-}" != "true" ]; then
                    log "SAFETY GUARD: Calling error_exit to prevent VM destruction"
                    error_exit "SAFETY GUARD: The following VMs exist in Terraform state but are NOT in the current configuration:" \
                        "  VMs that will be destroyed: $vms_to_destroy" \
                        "  Tfvars file: $tfvars_file" \
                        "  State location: $TF_ROOT" \
                        "" \
                        "  This would destroy existing VMs!" \
                        "  If you intend to destroy these VMs, set: THINKDEPLOY_ALLOW_DESTROY=true" \
                        "  Otherwise, ensure your configuration includes all VMs you want to keep." \
                        "  You can add them back via: ./setup.sh -> Option 2 (Compute/VM/LXC) -> Option 1 (Create VM)"
                else
                    warning "THINKDEPLOY_ALLOW_DESTROY=true: The following VMs will be destroyed: $vms_to_destroy"
                fi
            else
                log "SAFETY GUARD: No VMs will be destroyed (all state VMs are in tfvars)"
            fi
        fi
        
        # Safety check: state has VMs but tfvars doesn't (empty vms: {})
        # Only block if we're actually trying to manage VMs (i.e., if this is a VM deployment)
        # If we're only deploying LXCs or other resources, allow it
        if [ "$state_has_vms" = "true" ] && [ "$tfvars_has_vms" = "false" ]; then
            # Check if we're trying to deploy other resources (LXCs, storages, etc.)
            local tfvars_has_lxcs=false
            local tfvars_has_other=false
            local lxcs_count
            lxcs_count=$(jq -r '.lxcs // {} | keys | length' "$tfvars_file" 2>/dev/null || echo "0")
            if [ "$lxcs_count" -gt 0 ]; then
                tfvars_has_lxcs=true
                tfvars_has_other=true
            fi
            # Check for other resources
            local storages_count
            storages_count=$(jq -r '.storages // {} | keys | length' "$tfvars_file" 2>/dev/null || echo "0")
            local backup_jobs_count
            backup_jobs_count=$(jq -r '.backup_jobs // {} | keys | length' "$tfvars_file" 2>/dev/null || echo "0")
            local snapshots_count
            snapshots_count=$(jq -r '.snapshots // {} | keys | length' "$tfvars_file" 2>/dev/null || echo "0")
            if [ "$storages_count" -gt 0 ] || [ "$backup_jobs_count" -gt 0 ] || [ "$snapshots_count" -gt 0 ]; then
                tfvars_has_other=true
            fi
            # Check for networking, security, cluster configs
            if jq -e '.networking_config // {} | keys | length > 0' "$tfvars_file" >/dev/null 2>&1 || \
               jq -e '.security_config // {} | keys | length > 0' "$tfvars_file" >/dev/null 2>&1 || \
               jq -e '.cluster_config // {} | keys | length > 0' "$tfvars_file" >/dev/null 2>&1; then
                tfvars_has_other=true
            fi
            
            # Only block if we're NOT deploying other resources (meaning this is a VM-only deployment that would destroy VMs)
            if [ "$tfvars_has_other" = "false" ]; then
                if [ "${THINKDEPLOY_ALLOW_DESTROY:-}" != "true" ]; then
                    error_exit "SAFETY GUARD: Terraform state contains module.vm resources, but tfvars file has empty vms: {}." \
                        "  This would destroy existing VMs!" \
                        "  Tfvars file: $tfvars_file" \
                        "  State location: $TF_ROOT" \
                        "  If you intend to destroy resources, set: THINKDEPLOY_ALLOW_DESTROY=true" \
                        "  Otherwise, ensure your tfvars file includes the VMs you want to keep." \
                        "  You may have run terraform without the correct -var-file flag."
                else
                    warning "THINKDEPLOY_ALLOW_DESTROY=true: Proceeding with destroy operation"
                fi
            else
                # We're deploying other resources (LXCs, etc.), so it's safe to proceed
                log "SAFETY GUARD: State has VMs but tfvars has empty vms. However, deploying other resources (LXCs: $lxcs_count, Storages: $storages_count, etc.), so allowing deployment."
            fi
        fi
        
        # Additional safety: If setup.sh collected VMs but tfvars is empty (shouldn't happen if build_tfvars_file worked)
        if [ -n "${vms:-}" ] && [ "$tfvars_has_vms" = "false" ]; then
            if [ "${THINKDEPLOY_ALLOW_DESTROY:-}" != "true" ]; then
                error_exit "SAFETY GUARD: VMs were configured in setup.sh but tfvars file has empty vms: {}." \
                    "  This indicates build_tfvars_file() may have failed or tfvars file is incorrect." \
                    "  Tfvars file: $tfvars_file" \
                    "  VMs string length: ${#vms}" \
                    "  If you intend to proceed without VMs, set: THINKDEPLOY_ALLOW_DESTROY=true"
            fi
        fi
        
        # Additional check: if Deploy All was selected and we computed VMs but tfvars is empty
        if [ "${DEPLOY_ALL_SELECTED:-false}" = "true" ]; then
            local enabled_vms_in_tfvars
            enabled_vms_in_tfvars=$(jq -r '.vms // {} | to_entries | map(select(.value.enabled==true)) | length' "$tfvars_file" 2>/dev/null || echo "0")
            local total_vms_in_tfvars
            total_vms_in_tfvars=$(jq -r '.vms // {} | keys | length' "$tfvars_file" 2>/dev/null || echo "0")
            
            # Safety check: If user collected VMs (vms variable is set) but tfvars has empty vms
            if [ -n "${vms:-}" ] && [ "$total_vms_in_tfvars" -eq 0 ]; then
                error_exit "SAFETY GUARD: VMs were configured (setup.sh collected VMs) but tfvars file has empty vms: {}." \
                    "  Tfvars file: $tfvars_file" \
                    "  This would prevent VM deployment. Check build_tfvars_file() logic." \
                    "  If you intend to proceed without VMs, set: THINKDEPLOY_ALLOW_DESTROY=true"
            fi
            
            if [ "$enabled_vms_in_tfvars" -eq 0 ] && [ -n "${vms:-}" ]; then
                warning "Deploy All selected but tfvars has 0 enabled VMs. Checking if other resources exist..."
                local has_other_resources=false
                if jq -e '.lxcs // {} | keys | length > 0' "$tfvars_file" >/dev/null 2>&1 || \
                   jq -e '.storages // {} | keys | length > 0' "$tfvars_file" >/dev/null 2>&1 || \
                   jq -e '.networking_config // {} | keys | length > 0' "$tfvars_file" >/dev/null 2>&1; then
                    has_other_resources=true
                fi
                if [ "$has_other_resources" = "false" ]; then
                    error_exit "Deploy All selected but no resources configured in tfvars file." \
                        "  Tfvars file: $tfvars_file" \
                        "  This appears to be a configuration error."
                fi
            fi
        fi
    fi
    
    log "TF_ROOT=$TF_ROOT"
    log "TFVARS_FILE=$tfvars_file"
    local enabled_vms_log
    enabled_vms_log=$(jq -r '.vms // {} | to_entries | map(select(.value.enabled==true)) | length' "$tfvars_file" 2>/dev/null || echo "0")
    log "enabled_vms=$enabled_vms_log"
    
    echo "🔧 Terraform Deployment Steps:"
    echo "   1. terraform init -upgrade"
    echo "   2. terraform validate"
    echo "   3. terraform plan -var-file=\"$tfvars_file\" -out=\"$PLAN_FILE\""
    echo "   4. terraform apply -auto-approve \"$PLAN_FILE\""
    echo ""
    
    # Use subshell to change directory - works regardless of -chdir support
    # This ensures terraform runs in the correct directory without relying on -chdir flag
    (
      cd "$TF_ROOT" || error_exit "Failed to change to TF_ROOT=$TF_ROOT"
      
      log "Running terraform init -upgrade..."
      echo "📦 Step 1/4: Initializing Terraform..."
      echo "Working directory: $(pwd)"
      set +e  # Temporarily disable exit on error to capture exit code
      terraform init -upgrade
      local init_exit=$?
      set -e  # Re-enable exit on error
      if [ "$init_exit" -ne 0 ]; then
          error_exit "Terraform initialization failed (exit code: $init_exit). Check log: $LOG_FILE"
      fi
      log "Terraform initialization completed successfully"
      echo "✅ Terraform initialized"
      echo ""
      
      log "Running terraform validate..."
      echo "🔍 Step 2/4: Validating Terraform configuration..."
      set +e  # Temporarily disable exit on error to capture exit code
      terraform validate
      local validate_exit=$?
      set -e  # Re-enable exit on error
      if [ "$validate_exit" -ne 0 ]; then
          error_exit "Terraform validation failed (exit code: $validate_exit). Check log: $LOG_FILE"
      fi
      log "Terraform validation completed successfully"
      echo "✅ Configuration valid"
      echo ""
      
      log "Running terraform plan..."
      echo "📋 Step 3/4: Planning Terraform changes..."
      echo "Command: terraform plan -var-file=\"$tfvars_file\" -out=\"$PLAN_FILE\""
      set +e  # Temporarily disable exit on error to capture exit code
      terraform plan -var-file="$tfvars_file" -out="$PLAN_FILE" 2>&1 | tee /tmp/terraform-plan-output.log
      local plan_exit=$?
      set -e  # Re-enable exit on error
      if [ "$plan_exit" -ne 0 ]; then
          error_exit "Terraform plan failed (exit code: $plan_exit). Check output above."
      fi
      log "Terraform plan completed successfully"
      echo "✅ Plan completed - changes will be applied"
      echo ""
      
      # Check if plan file was created
      if [ ! -f "$PLAN_FILE" ]; then
          error_exit "Terraform plan file not created: $PLAN_FILE"
      fi
      
      log "Running terraform apply..."
      echo "🚀 Step 4/4: Applying Terraform changes..."
      echo "Command: terraform apply -auto-approve \"$PLAN_FILE\""
      set +e  # Temporarily disable exit on error to capture exit code
      terraform apply -auto-approve "$PLAN_FILE" 2>&1 | tee /tmp/terraform-apply-output.log
      local apply_exit=$?
      set -e  # Re-enable exit on error
      if [ "$apply_exit" -ne 0 ]; then
          error_exit "Terraform apply failed (exit code: $apply_exit). Check log: $LOG_FILE"
      fi
      log "Terraform apply completed successfully"
      echo "✅ Infrastructure deployment completed"
      echo ""
      
      log "Verifying terraform state..."
      echo "🔍 Verifying Terraform state..."
      set +e  # Temporarily disable exit on error to capture exit code
      local state_list_output
      state_list_output=$(terraform state list)
      local state_list_exit=$?
      set -e  # Re-enable exit on error
      
      if [ "$state_list_exit" -ne 0 ]; then
          error_exit "Failed to list Terraform state (exit code: $state_list_exit). Check log: $LOG_FILE"
      fi
      
      local state_resources
      state_resources=$(echo "$state_list_output" | grep -v "^$" | wc -l || echo "0")
      if [ "$state_resources" -eq 0 ]; then
          error_exit "Terraform state is empty - no resources found. Deployment failed or no resources were created."
      else
          log "Terraform state contains $state_resources resource(s)"
          echo "✅ Terraform state verified: $state_resources resource(s) managed" 1>&2
          echo "State resources:" 1>&2
          echo "$state_list_output" | sed 's/^/   /' 1>&2
          
          # Check specifically for VM resources if VMs were expected
          local expected_vms
          expected_vms=$(jq -r '.vms // {} | to_entries | map(select(.value.enabled==true)) | length' "$tfvars_file" 2>/dev/null || echo "0")
          if [ "$expected_vms" -gt 0 ]; then
              local vm_resources
              vm_resources=$(echo "$state_list_output" | grep -c "^module\.vm\[" || echo "0")
              if [ "$vm_resources" -eq 0 ]; then
                  warning "Expected $expected_vms VM(s) but found 0 module.vm resources in state"
                  log "State list output: $state_list_output"
              else
                  log "Verified: $vm_resources VM resource(s) in state (expected $expected_vms)"
                  echo "✅ VM resources verified: $vm_resources VM(s) in state" 1>&2
              fi
              
              # Try to get vm_ids output
              set +e
              local vm_ids_output
              vm_ids_output=$(terraform output -json vm_ids 2>/dev/null || echo "[]")
              set -e
              if [ "$vm_ids_output" != "[]" ] && [ -n "$vm_ids_output" ]; then
                  log "VM IDs output: $vm_ids_output"
                  echo "📋 VM IDs: $vm_ids_output" 1>&2
              fi
          fi
      fi
      
    ) || error_exit "Terraform deploy failed"
    
    log "=== RUN_TERRAFORM_DEPLOY COMPLETE ==="
    
    # After successful deployment, keep tfvars file but ensure secure permissions
    if [ -f "$tfvars_file" ]; then
        chmod 600 "$tfvars_file" || warning "Failed to set permissions on tfvars file"
        log "Tfvars file kept with secure permissions: $tfvars_file"
        log "WARNING: Tfvars file contains sensitive data (SSH keys, passwords). Keep it secure."
    fi
    
    # Print rerun commands using ABSOLUTE paths so they work from any directory
    echo "" 1>&2
    echo "╔══════════════════════════════════════════════════════════════╗" 1>&2
    echo "║              Terraform Rerun Commands                        ║" 1>&2
    echo "╚══════════════════════════════════════════════════════════════╝" 1>&2
    echo "" 1>&2
    echo "To rerun Terraform manually, use these commands (absolute paths):" 1>&2
    echo "" 1>&2
    echo "  cd \"$TF_ROOT\"" 1>&2
    echo "  terraform init -upgrade" 1>&2
    echo "  terraform validate" 1>&2
    echo "  terraform plan -var-file=\"$tfvars_file\" -out=\"$PLAN_FILE\"" 1>&2
    echo "  terraform apply -auto-approve \"$PLAN_FILE\"" 1>&2
    echo "" 1>&2
    echo "Or use the tfvars file directly:" 1>&2
    echo "  terraform plan -var-file=\"$tfvars_file\"" 1>&2
    echo "  terraform apply -var-file=\"$tfvars_file\" -auto-approve" 1>&2
    echo "" 1>&2
    echo "Tfvars file location: $tfvars_file" 1>&2
    echo "Pointer file: $REPO_ROOT/.thinkdeploy_last_tfvars" 1>&2
    echo "" 1>&2
    
    return 0
}

build_tfvars_file() {
    # Ensure GENERATED_DIR exists (absolute path based on REPO_ROOT)
    mkdir -p "$GENERATED_DIR" || error_exit "Failed to create generated directory: $GENERATED_DIR"
    
    # Verify TFVARS_FILE is absolute path
    if [[ "$TFVARS_FILE" != /* ]]; then
        error_exit "TFVARS_FILE must be absolute path, got: $TFVARS_FILE"
    fi
    
    # Parse cluster_configs if not already parsed (needed when DEPLOY_ALL_SELECTED=true skips old code)
    # Always parse if cluster_configs exists and AUTOSCALING_JSON is not set (CLUSTER_JSON might be initialized elsewhere)
    if [ -n "$cluster_configs" ] && [ -z "${AUTOSCALING_JSON:-}" ]; then
        # Initialize cluster and autoscaling JSON
        CLUSTER_JSON='{"create_cluster":false,"cluster_name":"","primary_node":"","join_node":"","ha_enabled":false,"ha_group_name":"","ha_nodes":[]}'
        AUTOSCALING_JSON=""
        local temp_configs="$cluster_configs"
        local LOOP_COUNT=0
        local MAX_LOOPS=100
        local PREV_LENGTH=0
        
        while [ -n "$temp_configs" ] && [ $LOOP_COUNT -lt $MAX_LOOPS ]; do
            ((LOOP_COUNT++))
            temp_configs=$(echo "$temp_configs" | sed 's/^[[:space:],]*//')
            local CURRENT_LENGTH=${#temp_configs}
            if [ $CURRENT_LENGTH -eq $PREV_LENGTH ] && [ $CURRENT_LENGTH -gt 0 ]; then
                break
            fi
            PREV_LENGTH=$CURRENT_LENGTH
            
            if [[ "$temp_configs" =~ ^([^:]+):(.+)$ ]]; then
                local KEY="${BASH_REMATCH[1]}"
                local REST="${BASH_REMATCH[2]}"
                # Trim whitespace and newlines from KEY
                KEY=$(echo "$KEY" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\n\r')
                
                if [[ "$REST" =~ ^\{ ]]; then
                    local DEPTH=0
                    local VALUE=""
                    for (( i=0; i<${#REST}; i++ )); do
                        local CHAR="${REST:$i:1}"
                        VALUE="$VALUE$CHAR"
                        if [ "$CHAR" = "{" ]; then
                            ((DEPTH++))
                        elif [ "$CHAR" = "}" ]; then
                            ((DEPTH--))
                            if [ $DEPTH -eq 0 ]; then
                                break
                            fi
                        fi
                    done
                    
                    local REMAINING="${REST:${#VALUE}}"
                    temp_configs=$(echo "$REMAINING" | sed 's/^[[:space:],]*//')
                    
                    if echo "$VALUE" | jq . > /dev/null 2>&1; then
                        case "$KEY" in
                            autoscaling)
                                local AS_GROUP=$(echo "$VALUE" | jq -r '.group // ""' 2>/dev/null)
                                local AS_MIN=$(echo "$VALUE" | jq -r '.min // 2' 2>/dev/null)
                                local AS_MAX=$(echo "$VALUE" | jq -r '.max // 10' 2>/dev/null)
                                local AS_SCALE_UP=$(echo "$VALUE" | jq -r '.scale_up // 80' 2>/dev/null)
                                local AS_SCALE_DOWN=$(echo "$VALUE" | jq -r '.scale_down // 30' 2>/dev/null)
                                if [ -n "$AS_GROUP" ]; then
                                    AUTOSCALING_JSON=$(jq -n \
                                        --arg group "$AS_GROUP" \
                                        --argjson min "$AS_MIN" \
                                        --argjson max "$AS_MAX" \
                                        --argjson scale_up "$AS_SCALE_UP" \
                                        --argjson scale_down "$AS_SCALE_DOWN" \
                                        '{
                                            group: $group,
                                            min: $min,
                                            max: $max,
                                            scale_up: $scale_up,
                                            scale_down: $scale_down
                                        }' 2>/dev/null)
                                    if [ $? -eq 0 ] && [ -n "$AUTOSCALING_JSON" ]; then
                                        log "Processed autoscaling config in build_tfvars_file: group=$AS_GROUP"
                                    fi
                                fi
                                ;;
                        esac
                    fi
                else
                    break
                fi
            else
                break
            fi
        done
    fi
    
    # CRITICAL: Preserve existing VMs and LXCs from Terraform state to prevent accidental destruction
    # Read existing VMs and LXCs from state and merge with new ones
    local existing_vms_json="{}"
    local existing_lxcs_json="{}"
    local state_list_output=""
    if [ -f "$REPO_ROOT/terraform.tfstate" ] || [ -f "$REPO_ROOT/.terraform/terraform.tfstate" ]; then
        set +e  # Temporarily disable exit on error
        state_list_output=$(terraform -chdir="$REPO_ROOT" state list 2>/dev/null || echo "")
        local state_vm_list
        state_vm_list=$(echo "$state_list_output" | grep "^module\.vm\[" | sed 's/^module\.vm\["\(.*\)"\]\.null_resource\.vm\[0\]$/\1/' || echo "")
        local state_lxc_list
        state_lxc_list=$(echo "$state_list_output" | grep "^module\.lxc\[" | sed 's/^module\.lxc\["\(.*\)"\]\.null_resource\.lxc\[0\]$/\1/' || echo "")
        set -e  # Re-enable exit on error
        
        if [ -n "$state_vm_list" ]; then
            log "Found existing VMs in state: $state_vm_list"
            # Build JSON of existing VMs from state
            for state_vm in $state_vm_list; do
                # Get VM configuration from state
                set +e
                local state_vm_config
                state_vm_config=$(terraform -chdir="$REPO_ROOT" state show "module.vm[\"$state_vm\"].null_resource.vm[0]" 2>/dev/null || echo "")
                set -e
                
                if [ -n "$state_vm_config" ]; then
                    # Extract VM attributes from state triggers
                    # Note: State stores values as strings, but we need to convert numbers properly
                    local state_node state_vmid state_cores state_memory state_disk state_storage state_network state_enabled
                    state_node=$(echo "$state_vm_config" | grep -E '^\s+"node"\s+=' | awk '{print $3}' | tr -d '"' || echo "local")
                    state_vmid=$(echo "$state_vm_config" | grep -E '^\s+"vmid"\s+=' | awk '{print $3}' | tr -d '"' || echo "")
                    state_cores=$(echo "$state_vm_config" | grep -E '^\s+"cores"\s+=' | awk '{print $3}' | tr -d '"' || echo "2")
                    state_memory=$(echo "$state_vm_config" | grep -E '^\s+"memory"\s+=' | awk '{print $3}' | tr -d '"' || echo "2048")
                    state_disk=$(echo "$state_vm_config" | grep -E '^\s+"disk"\s+=' | awk '{print $3}' | tr -d '"' || echo "20G")
                    state_storage=$(echo "$state_vm_config" | grep -E '^\s+"storage"\s+=' | awk '{print $3}' | tr -d '"' || echo "local-lvm")
                    state_network=$(echo "$state_vm_config" | grep -E '^\s+"network"\s+=' | awk '{print $3}' | tr -d '"' || echo "model=virtio,bridge=vmbr0")
                    # enabled might not be in state triggers (default to true)
                    local state_enabled_raw
                    state_enabled_raw=$(echo "$state_vm_config" | grep -E '^\s+"enabled"\s+=' | awk '{print $3}' | tr -d '"' || echo "")
                    if [ -z "$state_enabled_raw" ] || [ "$state_enabled_raw" = "null" ]; then
                        state_enabled="true"
                    else
                        state_enabled="$state_enabled_raw"
                    fi
                    
                    # Validate that we have all required fields
                    if [ -z "$state_vmid" ] || [ -z "$state_node" ]; then
                        warning "VM $state_vm in state is missing required fields (vmid or node), skipping preservation"
                    else
                        # Build VM entry JSON with proper types (numbers for vmid, cores, memory; strings for others)
                        # Use jq to build the JSON properly to ensure correct types
                        # Convert string values to numbers/booleans as needed
                        local existing_vm_entry
                        local jq_exit_code
                        existing_vm_entry=$(jq -n \
                            --arg node "$state_node" \
                            --arg vmid_str "$state_vmid" \
                            --arg cores_str "$state_cores" \
                            --arg memory_str "$state_memory" \
                            --arg disk "$state_disk" \
                            --arg storage "$state_storage" \
                            --arg network "$state_network" \
                            --arg enabled_str "$state_enabled" \
                            '{
                                node: $node,
                                vmid: ($vmid_str | tonumber),
                                cores: ($cores_str | tonumber),
                                memory: ($memory_str | tonumber),
                                disk: $disk,
                                storage: $storage,
                                network: $network,
                                enabled: (if $enabled_str == "true" then true else (if $enabled_str == "false" then false else true end) end)
                            }' 2>&1)
                        jq_exit_code=$?
                        
                        # Check if jq succeeded and output is valid JSON
                        if [ $jq_exit_code -eq 0 ] && [ -n "$existing_vm_entry" ] && echo "$existing_vm_entry" | jq -e . >/dev/null 2>&1; then
                            existing_vms_json=$(echo "$existing_vms_json" | jq ". + {\"$state_vm\": $existing_vm_entry}" 2>/dev/null || echo "$existing_vms_json")
                            log "Preserved existing VM from state: $state_vm (VMID: $state_vmid)" agent log
                        else
                            warning "Failed to build VM entry for $state_vm from state (jq exit: $jq_exit_code, output: ${existing_vm_entry:0:100}), skipping preservation" agent log
                        fi
                    fi
                fi
            done
        fi
        
        # Preserve existing LXCs from state
        if [ -n "$state_lxc_list" ]; then
            log "Found existing LXCs in state: $state_lxc_list"
            # Build JSON of existing LXCs from state
            for state_lxc in $state_lxc_list; do
                # Get LXC configuration from state
                set +e
                local state_lxc_config
                state_lxc_config=$(terraform -chdir="$REPO_ROOT" state show "module.lxc[\"$state_lxc\"].null_resource.lxc[0]" 2>/dev/null || echo "")
                set -e
                
                if [ -n "$state_lxc_config" ]; then
                    # Extract LXC attributes from state triggers
                    local state_lxc_node state_lxc_vmid state_lxc_cores state_lxc_memory state_lxc_rootfs state_lxc_storage state_lxc_ostemplate state_lxc_enabled
                    state_lxc_node=$(echo "$state_lxc_config" | grep -E '^\s+"node"\s+=' | awk '{print $3}' | tr -d '"' || echo "local")
                    state_lxc_vmid=$(echo "$state_lxc_config" | grep -E '^\s+"vmid"\s+=' | awk '{print $3}' | tr -d '"' || echo "")
                    state_lxc_cores=$(echo "$state_lxc_config" | grep -E '^\s+"cores"\s+=' | awk '{print $3}' | tr -d '"' || echo "2")
                    state_lxc_memory=$(echo "$state_lxc_config" | grep -E '^\s+"memory"\s+=' | awk '{print $3}' | tr -d '"' || echo "512")
                    state_lxc_rootfs=$(echo "$state_lxc_config" | grep -E '^\s+"rootfs"\s+=' | awk '{print $3}' | tr -d '"' || echo "local-lvm:8")
                    state_lxc_storage=$(echo "$state_lxc_config" | grep -E '^\s+"storage"\s+=' | awk '{print $3}' | tr -d '"' || echo "local-lvm")
                    state_lxc_ostemplate=$(echo "$state_lxc_config" | grep -E '^\s+"ostemplate"\s+=' | awk '{print $3}' | tr -d '"' || echo "")
                    # enabled might not be in state triggers (default to true)
                    local state_lxc_enabled_raw
                    state_lxc_enabled_raw=$(echo "$state_lxc_config" | grep -E '^\s+"enabled"\s+=' | awk '{print $3}' | tr -d '"' || echo "")
                    if [ -z "$state_lxc_enabled_raw" ] || [ "$state_lxc_enabled_raw" = "null" ]; then
                        state_lxc_enabled="true"
                    else
                        state_lxc_enabled="$state_lxc_enabled_raw"
                    fi
                    
                    # Validate that we have all required fields
                    if [ -z "$state_lxc_vmid" ] || [ -z "$state_lxc_node" ]; then
                        warning "LXC $state_lxc in state is missing required fields (vmid or node), skipping preservation"
                    else
                        # Build LXC entry JSON with proper types
                        local existing_lxc_entry
                        local lxc_jq_exit_code
                        existing_lxc_entry=$(jq -n \
                            --arg node "$state_lxc_node" \
                            --arg vmid_str "$state_lxc_vmid" \
                            --arg cores_str "$state_lxc_cores" \
                            --arg memory_str "$state_lxc_memory" \
                            --arg rootfs "$state_lxc_rootfs" \
                            --arg storage "$state_lxc_storage" \
                            --arg ostemplate "$state_lxc_ostemplate" \
                            --arg enabled_str "$state_lxc_enabled" \
                            '{
                                node: $node,
                                vmid: ($vmid_str | tonumber),
                                cores: ($cores_str | tonumber),
                                memory: ($memory_str | tonumber),
                                rootfs: $rootfs,
                                storage: $storage,
                                ostemplate: $ostemplate,
                                enabled: (if $enabled_str == "true" then true else (if $enabled_str == "false" then false else true end) end)
                            }' 2>&1)
                        lxc_jq_exit_code=$?
                        
                        # Check if jq succeeded and output is valid JSON
                        if [ $lxc_jq_exit_code -eq 0 ] && [ -n "$existing_lxc_entry" ] && echo "$existing_lxc_entry" | jq -e . >/dev/null 2>&1; then
                            existing_lxcs_json=$(echo "$existing_lxcs_json" | jq ". + {\"$state_lxc\": $existing_lxc_entry}" 2>/dev/null || echo "$existing_lxcs_json")
                            log "Preserved existing LXC from state: $state_lxc (VMID: $state_lxc_vmid)"
                        else
                            warning "Failed to build LXC entry for $state_lxc from state (jq exit: $lxc_jq_exit_code, output: ${existing_lxc_entry:0:100}), skipping preservation"
                        fi
                    fi
                fi
            done
        fi
    fi
    
    # Build JSON object for all terraform variables
    local TFVARS_JSON="{"
    
    # Add VMs - merge existing VMs from state with new VMs (new VMs override existing ones with same name)
    local final_vms_json="$existing_vms_json"
    if [ -n "$vms" ]; then
        # Process VMs and add missing required fields for cloud-init VMs
        # Cloud-init VMs may only have: node, vmid, template, cloud_init, user, ssh_key, enabled
        # But Terraform requires: node, vmid, cores, memory, disk, storage, network, enabled
        local processed_vms=""
        local vm_entry
        # Parse each VM entry (format: "vm_id":{...})
        # Use jq to properly parse and process the VMs JSON
        local vms_json="{${vms}}"
        if echo "$vms_json" | jq -e . >/dev/null 2>&1; then
            # Valid JSON - process each VM
            local vm_keys
            vm_keys=$(echo "$vms_json" | jq -r 'keys[]' 2>/dev/null || echo "")
            for vm_key in $vm_keys; do
                local vm_data
                vm_data=$(echo "$vms_json" | jq ".[\"$vm_key\"]" 2>/dev/null || echo "{}")
                # Check if this is a cloud-init VM (has template or cloud_init field)
                local has_template
                has_template=$(echo "$vm_data" | jq -r 'has("template") or has("cloud_init")' 2>/dev/null || echo "false")
                if [ "$has_template" = "true" ]; then
                    # Cloud-init VM - add missing required fields with defaults
                    local node_val
                    node_val=$(echo "$vm_data" | jq -r '.node // "local"' 2>/dev/null || echo "local")
                    local vmid_val
                    vmid_val=$(echo "$vm_data" | jq -r '.vmid // 100' 2>/dev/null || echo "100")
                    local cores_val
                    cores_val=$(echo "$vm_data" | jq -r '.cores // 2' 2>/dev/null || echo "2")
                    local memory_val
                    memory_val=$(echo "$vm_data" | jq -r '.memory // 2048' 2>/dev/null || echo "2048")
                    local disk_val
                    disk_val=$(echo "$vm_data" | jq -r '.disk // "20G"' 2>/dev/null || echo "20G")
                    local storage_val
                    storage_val=$(echo "$vm_data" | jq -r '.storage // "local-lvm"' 2>/dev/null || echo "local-lvm")
                    local network_val
                    network_val=$(echo "$vm_data" | jq -r '.network // "model=virtio,bridge=vmbr0"' 2>/dev/null || echo "model=virtio,bridge=vmbr0")
                    local enabled_val
                    enabled_val=$(echo "$vm_data" | jq -r '.enabled // true' 2>/dev/null || echo "true")
                    # Keep cloud-init specific fields
                    local template_val
                    template_val=$(echo "$vm_data" | jq -r '.template // ""' 2>/dev/null || echo "")
                    local cloud_init_val
                    cloud_init_val=$(echo "$vm_data" | jq -r '.cloud_init // false' 2>/dev/null || echo "false")
                    local user_val
                    user_val=$(echo "$vm_data" | jq -r '.user // ""' 2>/dev/null || echo "")
                    local ssh_key_val
                    ssh_key_val=$(echo "$vm_data" | jq -r '.ssh_key // ""' 2>/dev/null || echo "")
                    
                    # Build complete VM entry with all required fields
                    # Note: Terraform VM module doesn't support cloud-init fields (template, cloud_init, user, ssh_key)
                    # These fields are ignored - cloud-init functionality would need to be added to the VM module
                    local vm_entry_json="{\"node\":\"$node_val\",\"vmid\":$vmid_val,\"cores\":$cores_val,\"memory\":$memory_val,\"disk\":\"$disk_val\",\"storage\":\"$storage_val\",\"network\":\"$network_val\",\"enabled\":$enabled_val}"
                    
                    # Add to processed_vms
                    if [ -z "$processed_vms" ]; then
                        processed_vms="\"$vm_key\":$vm_entry_json"
                    else
                        processed_vms="$processed_vms,\"$vm_key\":$vm_entry_json"
                    fi
                    log "Processed cloud-init VM '$vm_key': added required fields (cores=$cores_val, memory=$memory_val, disk=$disk_val, storage=$storage_val, network=$network_val)"
                    if [ "$cloud_init_val" = "true" ] || [ -n "$template_val" ]; then
                        warning "Cloud-init VM '$vm_key': Cloud-init fields (template, cloud_init, user, ssh_key) are not supported by the Terraform VM module and will be ignored. VM will be created without cloud-init."
                    fi
                else
                    # Regular VM - use as-is (should already have all required fields)
                    local vm_entry_str
                    vm_entry_str=$(echo "$vms_json" | jq -c ".[\"$vm_key\"]" 2>/dev/null || echo "{}")
                    if [ -z "$processed_vms" ]; then
                        processed_vms="\"$vm_key\":$vm_entry_str"
                    else
                        processed_vms="$processed_vms,\"$vm_key\":$vm_entry_str"
                    fi
                fi
            done
            # Merge processed VMs with existing VMs from state (new VMs override existing ones)
            local new_vms_json="{$processed_vms}"
            final_vms_json=$(echo "$final_vms_json" | jq ". + $new_vms_json" 2>/dev/null || echo "$new_vms_json")
            log "Merged new VMs with existing VMs from state"
        else
            # Invalid JSON - use existing VMs from state only
            warning "VMs JSON is invalid, using existing VMs from state only: ${vms:0:100}..."
        fi
    fi
    
    # Convert final_vms_json to string format for TFVARS_JSON
    # Use jq to properly format the JSON object as a string
    local final_vms_string
    if [ "$final_vms_json" != "{}" ] && [ -n "$final_vms_json" ]; then
        # Validate the JSON first
        if echo "$final_vms_json" | jq -e . >/dev/null 2>&1; then
            # Extract the vms object content (without outer braces) and format it properly
            # jq -c outputs compact JSON, then we remove the outer braces
            final_vms_string=$(echo "$final_vms_json" | jq -c '.' 2>/dev/null | sed 's/^{\(.*\)}$/\1/' || echo "")
            if [ -n "$final_vms_string" ] && [ "$final_vms_string" != "null" ] && [ "$final_vms_string" != "{}" ]; then
                TFVARS_JSON="$TFVARS_JSON\"vms\":{$final_vms_string},"
                log "Added VMs to tfvars (including preserved VMs from state)"
            else
                warning "Failed to extract VMs string from final_vms_json, using empty vms: {}"
                TFVARS_JSON="$TFVARS_JSON\"vms\":{},"
            fi
        else
            warning "final_vms_json is invalid JSON, using empty vms: {}"
            TFVARS_JSON="$TFVARS_JSON\"vms\":{},"
        fi
    else
        TFVARS_JSON="$TFVARS_JSON\"vms\":{},"
    fi
    
    # Add LXCs - merge existing LXCs from state with new LXCs (new LXCs override existing ones with same name)
    local final_lxcs_json="$existing_lxcs_json"
    if [ -n "$lxcs" ]; then
        # Parse and process LXCs JSON
        local lxcs_json="{${lxcs}}"
        if echo "$lxcs_json" | jq -e . >/dev/null 2>&1; then
            # Valid JSON - merge with existing LXCs
            final_lxcs_json=$(echo "$final_lxcs_json" | jq ". + $lxcs_json" 2>/dev/null || echo "$lxcs_json")
            log "Merged new LXCs with existing LXCs from state"
        else
            warning "LXCs JSON is invalid, using existing LXCs from state only: ${lxcs:0:100}..."
        fi
    fi
    
    # Convert final_lxcs_json to string format for TFVARS_JSON
    local final_lxcs_string
    if [ "$final_lxcs_json" != "{}" ] && [ -n "$final_lxcs_json" ]; then
        if echo "$final_lxcs_json" | jq -e . >/dev/null 2>&1; then
            final_lxcs_string=$(echo "$final_lxcs_json" | jq -c '.' 2>/dev/null | sed 's/^{\(.*\)}$/\1/' || echo "")
            if [ -n "$final_lxcs_string" ] && [ "$final_lxcs_string" != "null" ] && [ "$final_lxcs_string" != "{}" ]; then
                TFVARS_JSON="$TFVARS_JSON\"lxcs\":{$final_lxcs_string},"
                log "Added LXCs to tfvars (including preserved LXCs from state)"
            else
                TFVARS_JSON="$TFVARS_JSON\"lxcs\":{},"
            fi
        else
            TFVARS_JSON="$TFVARS_JSON\"lxcs\":{},"
        fi
    else
        TFVARS_JSON="$TFVARS_JSON\"lxcs\":{},"
    fi
    
    # Add backup jobs
    if [ -n "$backup_jobs" ]; then
        TFVARS_JSON="$TFVARS_JSON\"backup_jobs\":{$backup_jobs},"
    else
        TFVARS_JSON="$TFVARS_JSON\"backup_jobs\":{},"
    fi
    
    # Add storages
    if [ -n "$storages" ]; then
        TFVARS_JSON="$TFVARS_JSON\"storages\":{$storages},"
    else
        TFVARS_JSON="$TFVARS_JSON\"storages\":{},"
    fi
    
    # Add networking
    if [ -n "$networking_configs" ]; then
        TFVARS_JSON="$TFVARS_JSON\"networking_config\":{$networking_configs},"
    else
        TFVARS_JSON="$TFVARS_JSON\"networking_config\":{},"
    fi
    
    # Add security config (already in JSON format from earlier parsing)
    if [ -n "$security_configs" ] && [ -n "${SECURITY_JSON:-}" ]; then
        TFVARS_JSON="$TFVARS_JSON\"security_config\":$SECURITY_JSON,"
    else
        TFVARS_JSON="$TFVARS_JSON\"security_config\":{},"
    fi
    
    # Add snapshots - parse if not already parsed
    local final_snapshots_json="{}"
    if [ -n "$snapshots" ]; then
        # Check if SNAPSHOTS_JSON was already parsed by old code
        if [ -n "${SNAPSHOTS_JSON:-}" ] && echo "$SNAPSHOTS_JSON" | jq -e . >/dev/null 2>&1; then
            final_snapshots_json="$SNAPSHOTS_JSON"
            log "Using pre-parsed SNAPSHOTS_JSON"
        else
            # Parse snapshots (snapshot:{...}) format
            log "Parsing snapshots in build_tfvars_file()..."
            # Remove leading/trailing whitespace and newlines
            local temp_snapshots=$(echo "$snapshots" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\n\r' | sed 's/^[[:space:]]*//')
            
            while [ -n "$temp_snapshots" ]; do
                # Match snapshot: prefix (with optional leading whitespace)
                if [[ "$temp_snapshots" =~ ^[[:space:]]*snapshot:(.+)$ ]]; then
                    local REST="${BASH_REMATCH[1]}"
                    
                    # Check if REST starts with {
                    
                    if [[ "$REST" =~ ^\{ ]]; then
                        local DEPTH=0
                        local VALUE=""
                        for (( i=0; i<${#REST}; i++ )); do
                            local CHAR="${REST:$i:1}"
                            VALUE="$VALUE$CHAR"
                            if [ "$CHAR" = "{" ]; then
                                ((DEPTH++))
                            elif [ "$CHAR" = "}" ]; then
                                ((DEPTH--))
                                if [ $DEPTH -eq 0 ]; then
                                    break
                                fi
                            fi
                        done
                        
                        temp_snapshots="${REST:${#VALUE}}"
                        temp_snapshots="${temp_snapshots#*,}"
                        
                        # Parse snapshot config and create unique key
                        if echo "$VALUE" | jq -e . >/dev/null 2>&1; then
                            local VMID
                            VMID=$(echo "$VALUE" | jq -r '.vmid // ""' 2>/dev/null)
                            local SNAPNAME
                            SNAPNAME=$(echo "$VALUE" | jq -r '.snapname // .name // ""' 2>/dev/null)
                            local SNAPSHOT_KEY="snap-${VMID}-${SNAPNAME}"
                            # Ensure the JSON has the correct structure for Terraform
                            local SNAPSHOT_OBJ
                            SNAPSHOT_OBJ=$(echo "$VALUE" | jq '{node: .node, vmid: .vmid, snapname: (.snapname // .name), description: (.description // ""), vm_type: (.vm_type // "qemu"), enabled: true}' 2>/dev/null || echo "$VALUE")
                            final_snapshots_json=$(echo "$final_snapshots_json" | jq ".\"$SNAPSHOT_KEY\" = $SNAPSHOT_OBJ" 2>/dev/null || echo "$final_snapshots_json")
                            log "Parsed snapshot: $SNAPSHOT_KEY"
                        else
                            warning "Invalid JSON in snapshot config: ${VALUE:0:100}..."
                        fi
                    else
                        break
                    fi
                else
                    break
                fi
            done
        fi
    fi
    
    # Validate final snapshots JSON
    if echo "$final_snapshots_json" | jq -e . >/dev/null 2>&1; then
        TFVARS_JSON="$TFVARS_JSON\"snapshots\":$final_snapshots_json,"
        log "Added snapshots to tfvars: $(echo "$final_snapshots_json" | jq 'keys | length' 2>/dev/null || echo "0") snapshot(s)"
    else
        warning "Invalid snapshots JSON, using empty snapshots: {}"
        TFVARS_JSON="$TFVARS_JSON\"snapshots\":{},"
    fi
    
    # Add cluster config (already in JSON format from earlier parsing)
    if [ -n "$cluster_configs" ] && [ -n "${CLUSTER_JSON:-}" ]; then
        TFVARS_JSON="$TFVARS_JSON\"cluster_config\":$CLUSTER_JSON,"
    else
        TFVARS_JSON="$TFVARS_JSON\"cluster_config\":{},"
    fi
    
    # Add autoscaling config (if configured)
    if [ -n "${AUTOSCALING_JSON:-}" ]; then
        TFVARS_JSON="$TFVARS_JSON\"autoscaling_config\":$AUTOSCALING_JSON,"
        log "Added autoscaling config to tfvars"
    else
        TFVARS_JSON="$TFVARS_JSON\"autoscaling_config\":{},"
    fi
    
    # Add SSH connection config (expand ~ in paths and validate)
    local pm_ssh_host="${TF_VAR_pm_ssh_host:-localhost}"
    local pm_ssh_user="${TF_VAR_pm_ssh_user:-root}"
    local pm_ssh_key="${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}"
    
    # Expand ~ to $HOME (handle both ~ and $HOME)
    pm_ssh_key="${pm_ssh_key/#\~/$HOME}"
    pm_ssh_key="${pm_ssh_key//\$HOME/$HOME}"
    # Try to resolve to absolute path
    if [[ "$pm_ssh_key" != /* ]]; then
        pm_ssh_key=$(readlink -f "$pm_ssh_key" 2>/dev/null || realpath "$pm_ssh_key" 2>/dev/null || echo "$pm_ssh_key")
    fi
    # Final validation - ensure key exists
    if [ ! -f "$pm_ssh_key" ]; then
        error_exit "SSH key file not found (expanded path): $pm_ssh_key"
    fi
    
    # Validate pm_ssh_host - warn if localhost but not validated
    if [ "$pm_ssh_host" = "localhost" ] || [ "$pm_ssh_host" = "127.0.0.1" ]; then
        # Check if we're actually on a Proxmox host
        if [ ! -d "/etc/pve" ] && ! command -v pvesh &> /dev/null; then
            warning "pm_ssh_host is 'localhost' but this doesn't appear to be a Proxmox host."
            warning "If you're running from a remote machine, set pm_ssh_host to the actual Proxmox node IP/hostname."
        fi
    fi
    
    TFVARS_JSON="$TFVARS_JSON\"pm_ssh_host\":\"$pm_ssh_host\","
    TFVARS_JSON="$TFVARS_JSON\"pm_ssh_user\":\"$pm_ssh_user\","
    TFVARS_JSON="$TFVARS_JSON\"pm_ssh_private_key_path\":\"$pm_ssh_key\","
    
    # Add vm_force_run (use timestamp to force VM creation on Deploy All)
    # However, preserve existing force_run from state if no VM config changes to avoid unnecessary replacements
    local existing_force_run=""
    if [ -n "$state_list_output" ] && echo "$state_list_output" | grep -q "module.vm"; then
        # Try to get force_run from the first VM in state (all VMs should have the same force_run value)
        local first_vm_in_state
        first_vm_in_state=$(echo "$state_list_output" | grep "module.vm\[" | head -1 | sed 's/.*module\.vm\["\([^"]*\)"\].*/\1/' || echo "")
        if [ -n "$first_vm_in_state" ]; then
            set +e
            local state_vm_force_run_config
            state_vm_force_run_config=$(terraform -chdir="$REPO_ROOT" state show "module.vm[\"$first_vm_in_state\"].null_resource.vm[0]" 2>/dev/null | grep -E '^\s+"force_run"\s+=' | awk '{print $3}' | tr -d '"' || echo "")
            set -e
            if [ -n "$state_vm_force_run_config" ]; then
                existing_force_run="$state_vm_force_run_config"
                log "Preserved existing force_run from state: $existing_force_run"
            fi
        fi
    fi
    
    # Only generate new force_run if:
    # 1. No existing force_run found in state (new deployment)
    # 2. There are new VMs being added (not just preserved from state)
    # 3. VM configurations have changed
    # For now, we'll preserve the existing force_run if it exists, to avoid unnecessary replacements
    # This can be overridden by setting THINKDEPLOY_FORCE_VM_RECREATE=true
    if [ -n "${THINKDEPLOY_FORCE_VM_RECREATE:-}" ] && [ "${THINKDEPLOY_FORCE_VM_RECREATE}" = "true" ]; then
        VM_FORCE_RUN=$(date +%s)
        log "Force VM recreate requested, generating new force_run: $VM_FORCE_RUN"
    elif [ -n "$existing_force_run" ]; then
        VM_FORCE_RUN="$existing_force_run"
        log "Preserving existing force_run to avoid unnecessary VM replacements: $VM_FORCE_RUN"
    else
        VM_FORCE_RUN=$(date +%s)
        log "No existing force_run found, generating new: $VM_FORCE_RUN"
    fi
    TFVARS_JSON="$TFVARS_JSON\"vm_force_run\":\"$VM_FORCE_RUN\""
    
    TFVARS_JSON="$TFVARS_JSON}"
    
    # Validate JSON and write to file (using absolute path)
    
    local json_validation_output
    json_validation_output=$(echo "$TFVARS_JSON" | jq . > "$TFVARS_FILE" 2>&1)
    local json_validation_exit=$?
    
    if [ "$json_validation_exit" -ne 0 ]; then
        log "ERROR: TFVARS_JSON validation failed. JSON preview (first 500 chars): ${TFVARS_JSON:0:500}"
        log "ERROR: jq validation output: $json_validation_output"
        error_exit "Failed to create valid tfvars JSON file at: $TFVARS_FILE" \
            "  JSON validation error: $json_validation_output" \
            "  Check the log file for more details: $LOG_FILE"
    fi
    
    # Immediately verify file exists
    if [ ! -f "$TFVARS_FILE" ]; then
        error_exit "Tfvars file was not created: $TFVARS_FILE"
    fi
    
    # Set secure permissions (contains secrets)
    chmod 600 "$TFVARS_FILE" || warning "Failed to set permissions on tfvars file"
    
    # Write pointer file for easy reference (always use absolute path)
    echo "$TFVARS_FILE" > "$REPO_ROOT/.thinkdeploy_last_tfvars" || error_exit "Failed to write pointer file: $REPO_ROOT/.thinkdeploy_last_tfvars"
    chmod 644 "$REPO_ROOT/.thinkdeploy_last_tfvars" || warning "Failed to set permissions on pointer file"
    
    # Log and print file details for verification
    log "Created tfvars file: $TFVARS_FILE"
    log "File verification: $(ls -la "$TFVARS_FILE" 2>/dev/null || echo 'FILE NOT FOUND')"
    echo "✅ Tfvars file created: $TFVARS_FILE" 1>&2
    echo "   $(ls -lh "$TFVARS_FILE" 2>/dev/null | awk '{print $1, $5, $9}')" 1>&2
    
    # Immediate verification with jq
    log "Verifying tfvars file structure..."
    if ! jq -e . "$TFVARS_FILE" >/dev/null 2>&1; then
        error_exit "Tfvars file is not valid JSON: $TFVARS_FILE"
    fi
    
    # Verify VMs section
    local vm_keys
    vm_keys=$(jq -r '.vms | keys | @json' "$TFVARS_FILE" 2>/dev/null || echo "[]")
    log "VMs in tfvars: $vm_keys"
    local vm_count
    vm_count=$(jq -r '.vms | keys | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
    echo "📋 VMs configured: $vm_count" 1>&2
    if [ -n "$vms" ]; then
        if [ "$vm_count" -eq 0 ]; then
            error_exit "VMs were configured but tfvars has 0 VMs. JSON structure issue." \
                "  VMs string length: ${#vms}" \
                "  Tfvars file: $TFVARS_FILE"
        fi
        log "Verified: $vm_count VM(s) in tfvars file"
    fi
    
    # Additional verification: log all sections
    log "Tfvars file verification complete:"
    log "  - VMs: $vm_count"
    log "  - LXCs: $(jq -r '.lxcs // {} | keys | length' "$TFVARS_FILE" 2>/dev/null || echo "0")"
    log "  - Backup jobs: $(jq -r '.backup_jobs // {} | keys | length' "$TFVARS_FILE" 2>/dev/null || echo "0")"
    log "  - Storages: $(jq -r '.storages // {} | keys | length' "$TFVARS_FILE" 2>/dev/null || echo "0")"
    
    # Verify SSH config is present
    if ! jq -e '.pm_ssh_host // empty' "$TFVARS_FILE" >/dev/null 2>&1; then
        warning "pm_ssh_host not found in tfvars, using default"
    else
        log "SSH config verified in tfvars: host=$(jq -r '.pm_ssh_host' "$TFVARS_FILE"), user=$(jq -r '.pm_ssh_user' "$TFVARS_FILE")"
    fi
    
    # If Deploy All was selected, deploy immediately
    if [ "${DEPLOY_ALL_SELECTED:-false}" = "true" ]; then
        # Use REPO_ROOT as TF_ROOT (already set at script start)
        TF_ROOT="$REPO_ROOT"
        
        # CRITICAL: Verify tfvars file exists and is valid
        if [ ! -f "$TFVARS_FILE" ]; then
            error_exit "Deploy All selected but tfvars file not found: $TFVARS_FILE"
        fi
        
        if ! jq -e . "$TFVARS_FILE" >/dev/null 2>&1; then
            error_exit "Deploy All selected but tfvars file is invalid JSON: $TFVARS_FILE"
        fi
        
        # Count enabled VMs and total VMs
        enabled_vms=$(jq -r '.vms // {} | to_entries | map(select(.value.enabled==true)) | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
        total_vms=$(jq -r '.vms // {} | keys | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
        log "DEBUG DeployAll: TFVARS_FILE=$TFVARS_FILE enabled_vms=$enabled_vms total_vms=$total_vms TF_ROOT=$TF_ROOT"
        
        # Safety check: If VMs were collected but tfvars has 0 VMs, abort
        if [ -n "$vms" ] && [ "$total_vms" -eq 0 ]; then
            error_exit "Deploy All selected: VMs were configured but tfvars has 0 VMs." \
                "  This indicates a bug in build_tfvars_file()." \
                "  Tfvars file: $TFVARS_FILE" \
                "  VMs string length: ${#vms}"
        fi
        
        # Count other resources
        enabled_lxcs=$(jq -r '.lxcs // {} | to_entries | map(select(.value.enabled != false)) | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
        total_lxcs=$(jq -r '.lxcs // {} | keys | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
        total_storages=$(jq -r '.storages // {} | keys | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
        total_backup_jobs=$(jq -r '.backup_jobs // {} | keys | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
        total_snapshots=$(jq -r '.snapshots // {} | keys | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
        has_networking=$(jq -e '.networking_config // {} | keys | length > 0' "$TFVARS_FILE" >/dev/null 2>&1 && echo "true" || echo "false")
        has_security=$(jq -e '.security_config // {} | keys | length > 0' "$TFVARS_FILE" >/dev/null 2>&1 && echo "true" || echo "false")
        has_cluster=$(jq -e '.cluster_config // {} | keys | length > 0' "$TFVARS_FILE" >/dev/null 2>&1 && echo "true" || echo "false")
        
        log "DEBUG DeployAll: enabled_vms=$enabled_vms total_vms=$total_vms enabled_lxcs=$enabled_lxcs total_lxcs=$total_lxcs"
        
        if [ "$enabled_vms" -gt 0 ]; then
            log "Deploy All: Deploying $enabled_vms enabled VM(s) from $TFVARS_FILE"
            run_terraform_deploy "$TFVARS_FILE"
            # Exit after successful deployment
            exit 0
        elif [ "$enabled_lxcs" -gt 0 ]; then
            log "Deploy All: Deploying $enabled_lxcs enabled LXC container(s) from $TFVARS_FILE"
            run_terraform_deploy "$TFVARS_FILE"
            exit 0
        elif [ "$total_vms" -gt 0 ]; then
            warning "Deploy All selected: $total_vms VM(s) found but 0 are enabled. Checking for other resources..."
            # Check for other resources
            local has_other_resources=false
            if [ "$total_lxcs" -gt 0 ] || [ "$total_storages" -gt 0 ] || [ "$total_backup_jobs" -gt 0 ] || [ "$total_snapshots" -gt 0 ] || [ "$has_networking" = "true" ] || [ "$has_security" = "true" ] || [ "$has_cluster" = "true" ]; then
                has_other_resources=true
            fi
            if [ "$has_other_resources" = "true" ]; then
                log "Deploy All: Deploying other resources (no enabled VMs)"
                run_terraform_deploy "$TFVARS_FILE"
                exit 0
            else
                error_exit "Deploy All selected but no enabled VMs and no other resources found in tfvars ($TFVARS_FILE)"
            fi
        elif [ "$total_lxcs" -gt 0 ] || [ "$total_storages" -gt 0 ] || [ "$total_backup_jobs" -gt 0 ] || [ "$total_snapshots" -gt 0 ] || [ "$has_networking" = "true" ] || [ "$has_security" = "true" ] || [ "$has_cluster" = "true" ]; then
            # No VMs but have other resources - deploy them
            log "Deploy All: Deploying resources (no VMs, but have other resources)"
            log "DEBUG DeployAll: total_lxcs=$total_lxcs total_storages=$total_storages total_backup_jobs=$total_backup_jobs total_snapshots=$total_snapshots"
            run_terraform_deploy "$TFVARS_FILE"
            exit 0
        else
            error_exit "Deploy All selected but no resources found in tfvars ($TFVARS_FILE)." \
                "  VMs: $total_vms, LXCs: $total_lxcs, Storages: $total_storages, Backup jobs: $total_backup_jobs, Snapshots: $total_snapshots"
        fi
    fi
    
    # Validate that VMs are actually in the file (if configured)
    if [ -n "$vms" ]; then
        TFVARS_VM_COUNT=$(jq '.vms | keys | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
        if [ "$TFVARS_VM_COUNT" -eq 0 ]; then
            warning "VMs were configured but tfvars file has 0 VMs - checking JSON structure..."
            log "VMs string (first 200 chars): ${vms:0:200}..." 1>&2
            log "tfvars vms section: $(jq '.vms' "$TFVARS_FILE" 2>/dev/null)" 1>&2
            error_exit "VMs configured but not written to tfvars file. Check JSON structure."
        else
            log "Verified: $TFVARS_VM_COUNT VM(s) written to tfvars file"
        fi
    fi
}

# Check if we have any configurations to deploy
HAS_CONFIGS=false
[ -n "$vms" ] && HAS_CONFIGS=true
[ -n "$lxcs" ] && HAS_CONFIGS=true
[ -n "$backup_jobs" ] && HAS_CONFIGS=true
[ -n "$storages" ] && HAS_CONFIGS=true
[ -n "$networking_configs" ] && HAS_CONFIGS=true
[ -n "$security_configs" ] && HAS_CONFIGS=true
[ -n "$cluster_configs" ] && HAS_CONFIGS=true
[ -n "$snapshots" ] && HAS_CONFIGS=true

# CRITICAL: If Deploy All was selected, we MUST build tfvars and deploy
# Even if HAS_CONFIGS is false, build_tfvars_file will handle empty configs
if [ "${DEPLOY_ALL_SELECTED:-false}" = "true" ]; then
    log "Deploy All selected - will build tfvars and deploy immediately"
    log "DEBUG: DEPLOY_ALL_SELECTED=true, HAS_CONFIGS=$HAS_CONFIGS, vms length=${#vms}"
    # build_tfvars_file will handle the deployment
elif [ "$HAS_CONFIGS" = "false" ]; then
    warning "No configurations to deploy. Exiting."
    echo "⚠️  No resources configured. Please configure at least one resource before deploying." 1>&2
    exit 0
fi

# Build tfvars file (will be used for plan and apply)
# CRITICAL: This MUST run for Deploy All to work
# Use set +e temporarily to ensure we always try to build tfvars even if previous code had issues
set +e
log "Building tfvars file..."
log "DEBUG: About to call build_tfvars_file(), REPO_ROOT=$REPO_ROOT, TFVARS_FILE=$TFVARS_FILE"
build_tfvars_file
BUILD_TFVARS_EXIT=$?
set -e
if [ $BUILD_TFVARS_EXIT -ne 0 ]; then
    error_exit "build_tfvars_file() failed with exit code $BUILD_TFVARS_EXIT"
fi
log "DEBUG: build_tfvars_file() completed successfully"

# Verify tfvars file was created (build_tfvars_file should have already verified, but double-check)
if [ ! -f "$TFVARS_FILE" ]; then
    error_exit "CRITICAL: Tfvars file was not created: $TFVARS_FILE"
fi

# If Deploy All was selected, build_tfvars_file should have already called run_terraform_deploy
# and exited. If we reach here, something went wrong.
if [ "${DEPLOY_ALL_SELECTED:-false}" = "true" ]; then
    error_exit "CRITICAL: Deploy All was selected but run_terraform_deploy was not called." \
        "  This indicates a bug in build_tfvars_file()." \
        "  Tfvars file: $TFVARS_FILE"
fi

# DEBUG: Deploy All handler - immediately after tfvars creation
log "DEBUG DeployAll: TF_MODE=${TF_MODE:-unset}"
log "DEBUG DeployAll: TFVARS_FILE=$TFVARS_FILE"
log "DEBUG DeployAll: HAS_CONFIGS=$HAS_CONFIGS"

# Determine TF_ROOT for debug logging
script_dir_debug="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_ROOT_DEBUG="$script_dir_debug"
if [ ! -f "$TF_ROOT_DEBUG/main.tf" ]; then
    search_dir_debug="$TF_ROOT_DEBUG"
    while [ "$search_dir_debug" != "/" ]; do
        if [ -f "$search_dir_debug/main.tf" ]; then
            TF_ROOT_DEBUG="$search_dir_debug"
            break
        fi
        search_dir_debug="$(dirname "$search_dir_debug")"
    done
fi
log "DEBUG DeployAll: TF_ROOT=$TF_ROOT_DEBUG"

# Count enabled VMs in tfvars file
enabled_vms_count=$(jq -r '.vms // {} | to_entries | map(select(.value.enabled != false)) | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
log "DEBUG DeployAll: enabled_vms=$enabled_vms_count"

# Set TF_MODE default if missing
TF_MODE=${TF_MODE:-apply}

# HARD RULE: If enabled VMs > 0, MUST call run_terraform_deploy
# This will be enforced later, but log the requirement now
if [ "$enabled_vms_count" -gt 0 ]; then
    log "DEBUG DeployAll: enabled_vms > 0, run_terraform_deploy MUST be called"
fi

# Validate and clean VMs/LXCs before building JSON
# Remove any LXC containers that might have been added to vms by mistake
log "Validating and cleaning VMs/LXCs configuration..."
if [ -n "$vms" ]; then
    # Build a temporary JSON object to parse with jq
    temp_json="{${vms}}"
    
    # Use jq to separate VMs from LXCs
    if echo "$temp_json" | jq . > /dev/null 2>&1; then
        cleaned_vms=""
        moved_to_lxcs=""
        
        # Get all keys from the JSON
        keys=$(echo "$temp_json" | jq -r 'keys[]' 2>/dev/null)
        
        for key in $keys; do
            entry_json=$(echo "$temp_json" | jq "{\"$key\": .$key}" 2>/dev/null)
            entry_str=$(echo "$entry_json" | jq -c '.' 2>/dev/null | sed 's/^{"\([^"]*\)":\(.*\)}$/"\1":\2/')
            
            # Check if this entry has rootfs (LXC) or disk+network (VM)
            has_rootfs=$(echo "$entry_json" | jq -e ".[\"$key\"] | has(\"rootfs\")" 2>/dev/null)
            has_disk=$(echo "$entry_json" | jq -e ".[\"$key\"] | has(\"disk\")" 2>/dev/null)
            has_network=$(echo "$entry_json" | jq -e ".[\"$key\"] | has(\"network\")" 2>/dev/null)
            
            if [ "$has_rootfs" = "true" ] && [ "$has_disk" != "true" ]; then
                # This is an LXC container
                if [ -z "$moved_to_lxcs" ]; then
                    moved_to_lxcs="$entry_str"
                else
                    moved_to_lxcs="$moved_to_lxcs,$entry_str"
                fi
                log "Warning: Found LXC container '$key' in VMs, moving to LXCs" 1>&2
            elif [ "$has_disk" = "true" ] && [ "$has_network" = "true" ]; then
                # This is a valid VM
                if [ -z "$cleaned_vms" ]; then
                    cleaned_vms="$entry_str"
                else
                    cleaned_vms="$cleaned_vms,$entry_str"
                fi
            elif echo "$entry_json" | jq -e ".[\"$key\"] | has(\"template\") or has(\"cloud_init\")" > /dev/null 2>&1; then
                # VM with cloud-init
                if [ -z "$cleaned_vms" ]; then
                    cleaned_vms="$entry_str"
                else
                    cleaned_vms="$cleaned_vms,$entry_str"
                fi
            else
                # Unknown type - check if it has rootfs (LXC)
                if [ "$has_rootfs" = "true" ]; then
                    # LXC container
                    if [ -z "$moved_to_lxcs" ]; then
                        moved_to_lxcs="$entry_str"
                    else
                        moved_to_lxcs="$moved_to_lxcs,$entry_str"
                    fi
                    log "Warning: Found LXC container '$key' in VMs (by rootfs), moving to LXCs" 1>&2
                else
                    # Unknown type, keep in VMs but warn
                    log "Warning: Unknown resource type for '$key', keeping in VMs" 1>&2
                    if [ -z "$cleaned_vms" ]; then
                        cleaned_vms="$entry_str"
                    else
                        cleaned_vms="$cleaned_vms,$entry_str"
                    fi
                fi
            fi
        done
        
        vms="$cleaned_vms"
        if [ -n "$moved_to_lxcs" ]; then
            if [ -z "$lxcs" ]; then
                lxcs="$moved_to_lxcs"
            else
                lxcs="$lxcs,$moved_to_lxcs"
            fi
        fi
    else
        # If JSON parsing fails, use simple string matching as fallback
        log "Warning: Could not parse VMs JSON, using fallback method..." 1>&2
        cleaned_vms=""
        moved_to_lxcs=""
        IFS=',' read -ra VM_ENTRIES <<< "$vms"
        for entry in "${VM_ENTRIES[@]}"; do
            # Simple check: if it has "rootfs" but not "disk", it's LXC
            if [[ "$entry" == *"rootfs"* ]] && [[ ! "$entry" == *"disk"* ]]; then
                if [ -z "$moved_to_lxcs" ]; then
                    moved_to_lxcs="$entry"
                else
                    moved_to_lxcs="$moved_to_lxcs,$entry"
                fi
                log "Warning: Found LXC container in VMs (fallback), moving to LXCs" 1>&2
            elif [[ "$entry" == *"disk"* ]] && [[ "$entry" == *"network"* ]]; then
                if [ -z "$cleaned_vms" ]; then
                    cleaned_vms="$entry"
                else
                    cleaned_vms="$cleaned_vms,$entry"
                fi
            else
                # Default: keep in VMs
                if [ -z "$cleaned_vms" ]; then
                    cleaned_vms="$entry"
                else
                    cleaned_vms="$cleaned_vms,$entry"
                fi
            fi
        done
        vms="$cleaned_vms"
        if [ -n "$moved_to_lxcs" ]; then
            if [ -z "$lxcs" ]; then
                lxcs="$moved_to_lxcs"
            else
                lxcs="$lxcs,$moved_to_lxcs"
            fi
        fi
    fi
fi

log "Validating JSON syntax..."
if [ -n "$vms" ] && ! echo "{$vms}" | jq . > /dev/null 2>&1; then
    error_exit "Invalid JSON syntax in vms configuration"
fi

if [ -n "$backup_jobs" ] && ! echo "{$backup_jobs}" | jq . > /dev/null 2>&1; then
    error_exit "Invalid JSON syntax in backup_jobs configuration"
fi

if [ -n "$lxcs" ] && ! echo "{$lxcs}" | jq . > /dev/null 2>&1; then
    error_exit "Invalid JSON syntax in lxcs configuration"
fi

if [ -n "$storages" ] && ! echo "{$storages}" | jq . > /dev/null 2>&1; then
    error_exit "Invalid JSON syntax in storages configuration"
fi

log "JSON syntax validation passed"

# Preflight validation function
preflight_checks() {
    log "Running preflight checks..."
    echo "🔍 Running preflight validation..." 1>&2
    
    local errors=0
    
    # Check pvesh availability
    if [ "$PROXMOX_CLI_METHOD" != "pvesh" ] && [ "$PROXMOX_CLI_METHOD" != "proxmoxer" ]; then
        warning "Proxmox CLI tool (pvesh or proxmoxer) not available"
        echo "⚠️  Proxmox CLI not found - some operations may fail" 1>&2
        ((errors++))
    fi
    
    # Check SSH connectivity
    if [ -n "${TF_VAR_pm_ssh_host:-}" ] && [ -n "${TF_VAR_pm_ssh_user:-}" ]; then
        log "Testing SSH connectivity to ${TF_VAR_pm_ssh_user}@${TF_VAR_pm_ssh_host}..."
        if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}" \
            "${TF_VAR_pm_ssh_user}@${TF_VAR_pm_ssh_host}" "echo 'SSH OK'" > /dev/null 2>&1; then
            error_exit "SSH connection to ${TF_VAR_pm_ssh_user}@${TF_VAR_pm_ssh_host} failed. Check SSH key and connectivity."
        fi
        log "SSH connectivity verified"
    fi
    
    # Check node existence (if VMs/LXCs configured)
    if [ -n "$vms" ] || [ -n "$lxcs" ]; then
        if [ -n "${TF_VAR_pm_ssh_host:-}" ] && [ "$PROXMOX_CLI_METHOD" = "pvesh" ]; then
            log "Validating node existence and name matching..."
            # Get actual Proxmox nodes
            SSH_KEY_EXPANDED="${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}"
            SSH_KEY_EXPANDED="${SSH_KEY_EXPANDED/#\~/$HOME}"
            PROXMOX_NODES=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY_EXPANDED" \
                "${TF_VAR_pm_ssh_user:-root}@${TF_VAR_pm_ssh_host:-localhost}" \
                "pvesh get /nodes --output-format json 2>/dev/null" | jq -r '.[].node' 2>/dev/null | sort || echo "")
            
            if [ -z "$PROXMOX_NODES" ]; then
                warning "Could not retrieve Proxmox node list"
                echo "⚠️  Node validation skipped (cannot connect to Proxmox)" 1>&2
                ((errors++))
            else
                log "Available Proxmox nodes: $PROXMOX_NODES"
                # Extract unique nodes from vms and lxcs
                ALL_NODES=$(echo "{$vms}{$lxcs}" | jq -r '.[] | .node' 2>/dev/null | sort -u || echo "")
                for node in $ALL_NODES; do
                    if [ -n "$node" ]; then
                        log "Checking node: $node"
                        # Check exact match (case-sensitive)
                        if ! echo "$PROXMOX_NODES" | grep -q "^${node}$"; then
                            error_exit "Node '$node' not found in Proxmox. Available nodes: $(echo $PROXMOX_NODES | tr '\n' ' ')"
                        fi
                        # Verify node is accessible
                        if ! ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_EXPANDED" \
                            "${TF_VAR_pm_ssh_user:-root}@${TF_VAR_pm_ssh_host:-localhost}" \
                            "pvesh get /nodes/$node/status" > /dev/null 2>&1; then
                            warning "Node '$node' exists but not accessible"
                            echo "⚠️  Node '$node' validation failed" 1>&2
                            ((errors++))
                        else
                            log "Node '$node' verified"
                        fi
                    fi
                done
            fi
        fi
    fi
    
    # Check VMID availability (if VMs/LXCs configured)
    if [ -n "$vms" ] || [ -n "$lxcs" ]; then
        if [ -n "${TF_VAR_pm_ssh_host:-}" ] && [ "$PROXMOX_CLI_METHOD" = "pvesh" ]; then
            log "Checking VMID availability..."
            # Extract VMIDs
            ALL_VMIDS=$(echo "{$vms}{$lxcs}" | jq -r '.[] | .vmid' 2>/dev/null || echo "")
            for vmid in $ALL_VMIDS; do
                if [ -n "$vmid" ]; then
                    # Get first node (assuming all VMs on same node for this check)
                    NODE=$(echo "{$vms}{$lxcs}" | jq -r ".[] | select(.vmid == $vmid) | .node" 2>/dev/null | head -1)
                    if [ -n "$NODE" ]; then
                        # Check if VMID exists
                        EXISTING=$(ssh -o StrictHostKeyChecking=no -i "${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}" \
                            "${TF_VAR_pm_ssh_user:-root}@${TF_VAR_pm_ssh_host:-localhost}" \
                            "pvesh get /nodes/$NODE/qemu/$vmid 2>/dev/null || pvesh get /nodes/$NODE/lxc/$vmid 2>/dev/null" 2>/dev/null | wc -l)
                        if [ "$EXISTING" -gt 0 ]; then
                            warning "VMID $vmid already exists on node $NODE"
                            echo "⚠️  VMID $vmid is already in use" 1>&2
                            ((errors++))
                        else
                            log "VMID $vmid is available"
                        fi
                    fi
                fi
            done
        fi
    fi
    
    # Check storage existence (if VMs/LXCs configured)
    if [ -n "$vms" ] || [ -n "$lxcs" ]; then
        if [ -n "${TF_VAR_pm_ssh_host:-}" ] && [ "$PROXMOX_CLI_METHOD" = "pvesh" ]; then
            log "Validating storage existence..."
            # Extract unique storage names
            ALL_STORAGES=$(echo "{$vms}{$lxcs}" | jq -r '.[] | .storage' 2>/dev/null | sort -u || echo "")
            for storage in $ALL_STORAGES; do
                if [ -n "$storage" ]; then
                    # Get first node
                    NODE=$(echo "{$vms}{$lxcs}" | jq -r ".[] | select(.storage == \"$storage\") | .node" 2>/dev/null | head -1)
                    if [ -n "$NODE" ]; then
                        if ! ssh -o StrictHostKeyChecking=no -i "${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}" \
                            "${TF_VAR_pm_ssh_user:-root}@${TF_VAR_pm_ssh_host:-localhost}" \
                            "pvesh get /nodes/$NODE/storage/$storage/status" > /dev/null 2>&1; then
                            warning "Storage '$storage' not found on node $NODE"
                            echo "⚠️  Storage '$storage' validation failed" 1>&2
                            ((errors++))
                        else
                            log "Storage '$storage' verified"
                        fi
                    fi
                fi
            done
        fi
    fi
    
    if [ $errors -gt 0 ]; then
        warning "Preflight checks found $errors issue(s)"
        echo "⚠️  Preflight validation found issues. Continuing anyway..." 1>&2
        return 1
    else
        log "All preflight checks passed"
        echo "✅ Preflight validation successful" 1>&2
        return 0
    fi
}

# Pre-deployment validation
echo "╔══════════════════════════════════════════════════════════════╗" 1>&2
echo "║                    Pre-deployment Validation                ║" 1>&2
echo "╚══════════════════════════════════════════════════════════════╝" 1>&2
echo "" 1>&2

# Run preflight checks first
preflight_checks || true

log "Running pre-deployment validation (with ${VALIDATION_TIMEOUT}s timeout)..."
echo "⏳ Quick validation (${VALIDATION_TIMEOUT}s timeout)..." 1>&2

# Run terraform plan with timeout (disable exit on error temporarily)
set +e
echo "🔍 Running terraform plan to check configuration..." 1>&2

# Check for state lock and handle it
# Kill any stuck terraform processes first
pkill -9 -f "terraform plan" 2>/dev/null || true
pkill -9 -f "timeout.*terraform" 2>/dev/null || true
sleep 1

# Try to unlock any existing locks before running plan
if [ -f ".terraform.tfstate.lock.info" ]; then
    log "Detected Terraform state lock, attempting to unlock..."
    # Extract lock ID from lock file
    LOCK_ID=$(grep -E "ID:" .terraform.tfstate.lock.info 2>/dev/null | sed -E 's/.*ID:[[:space:]]*([a-f0-9-]+).*/\1/' | head -1)
    if [ -n "$LOCK_ID" ]; then
        terraform force-unlock -force "$LOCK_ID" 2>/dev/null && log "Unlocked state with ID: $LOCK_ID" || true
    fi
    rm -f .terraform.tfstate.lock.info 2>/dev/null || true
fi

plan_command="terraform plan -var-file=\"$TFVARS_FILE\""
timeout $VALIDATION_TIMEOUT bash -c "$plan_command" 2>&1 | tee -a "$LOG_FILE"
PLAN_EXIT_CODE=$?
set -e

if [ $PLAN_EXIT_CODE -eq 124 ]; then
    warning "Pre-deployment validation timed out after ${VALIDATION_TIMEOUT} seconds"
    echo "⚡ Validation timeout - proceeding with deployment" 1>&2
    echo "⚡ Full validation will run during terraform apply" 1>&2
    echo "" 1>&2
    echo "This is normal - continuing with deployment..." 1>&2
elif [ $PLAN_EXIT_CODE -eq 0 ]; then
    log "Pre-deployment validation passed"
    echo "✅ Configuration validation successful" 1>&2
else
    echo "" 1>&2
    echo "❌ Pre-deployment validation failed (exit code: $PLAN_EXIT_CODE)" 1>&2
    echo "📋 Check the error details above" 1>&2
    echo "" 1>&2
    echo "Options:" 1>&2
    echo "  f - Fix configuration and retry" 1>&2
    echo "  s - Skip validation and deploy anyway" 1>&2
    echo "  c - Cancel deployment" 1>&2
    read -p "What would you like to do? (f/s/c): " error_action
    
    case $error_action in
        [Ff]*)
            echo "Please fix the configuration and run the script again" 1>&2
            exit 1
            ;;
        [Ss]*)
            echo "⚠️  Skipping validation - proceeding with deployment..." 1>&2
            ;;
        [Cc]*|*)
            echo "Deployment cancelled" 1>&2
            exit 0
            ;;
    esac
fi

# Final deployment
# Only show deployment options if validation passed or was skipped
if [ $PLAN_EXIT_CODE -eq 0 ] || [ $PLAN_EXIT_CODE -eq 124 ]; then
    echo ""
    echo "Options:" 1>&2
    echo "  y - Proceed with deployment (default)" 1>&2
    echo "  s - Skip validation and deploy directly" 1>&2
    echo "  n - Cancel deployment" 1>&2
    read -p "Proceed with infrastructure deployment? (Y/s/n): " deploy_now
    deploy_now=${deploy_now:-y}  # Default to 'y' if empty
else
    # If validation failed and user chose to skip, set deploy_now to 's'
    deploy_now="s"
fi

if [[ "$deploy_now" =~ ^[Yy]$ ]] || [[ "$deploy_now" =~ ^[Ss]$ ]]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗" 1>&2
    echo "║                    Deploying Infrastructure                 ║" 1>&2
    echo "╚══════════════════════════════════════════════════════════════╝" 1>&2
    echo "" 1>&2
    
    if [[ "$deploy_now" =~ ^[Ss]$ ]]; then
        log "Starting infrastructure deployment (validation skipped)..."
        echo "⚡ Deploying directly without pre-validation..." 1>&2
    else
        log "Starting infrastructure deployment..."
    fi
    
    # Cluster creation is now handled by Terraform only
    # Terraform will check if cluster exists and skip creation if it does
    if [ -n "$cluster_configs" ]; then
        log "Cluster configuration will be deployed via Terraform"
        echo "ℹ️  Cluster configuration will be handled by Terraform (checks if cluster exists)" 1>&2
    fi
    
    # HARD RULE: If enabled VMs > 0, MUST call run_terraform_deploy
    # Count enabled VMs in tfvars file
    enabled_vms_check=$(jq -r '.vms // {} | to_entries | map(select(.value.enabled != false)) | length' "$TFVARS_FILE" 2>/dev/null || echo "0")
    
    log "DEBUG DeployAll: Checking enabled VMs before deploy: $enabled_vms_check"
    echo "🔍 Checking deployment requirements..." 1>&2
    
    if [ "$enabled_vms_check" -gt 0 ]; then
        log "DEBUG DeployAll: enabled_vms=$enabled_vms_check > 0, calling run_terraform_deploy"
        echo "🚀 Deploying $enabled_vms_check enabled VM(s)..." 1>&2
        
        # Run complete Terraform deployment orchestration
        run_terraform_deploy "$TFVARS_FILE"
        TF_EXIT_CODE=$?
        
        # Verify that run_terraform_deploy was actually called
        if [ -z "${TF_EXIT_CODE:-}" ]; then
            error_exit "VMs requested but deploy skipped. run_terraform_deploy did not set TF_EXIT_CODE. This is a bug."
        fi
    else
        # No enabled VMs, but still deploy if other resources exist
        if [ "$HAS_CONFIGS" = "true" ]; then
            log "DEBUG DeployAll: No enabled VMs, but HAS_CONFIGS=true, calling run_terraform_deploy"
            echo "🚀 Deploying other infrastructure resources..." 1>&2
            run_terraform_deploy "$TFVARS_FILE"
            TF_EXIT_CODE=$?
        else
            warning "No enabled VMs and no other configurations to deploy"
            TF_EXIT_CODE=0
        fi
    fi
    
    # FATAL: If we reach here and enabled VMs > 0 but run_terraform_deploy wasn't called
    if [ "$enabled_vms_check" -gt 0 ] && [ -z "${TF_EXIT_CODE:-}" ]; then
        error_exit "VMs requested but deploy skipped. This is a bug."
    fi
    
    # Cleanup and final status
    if [ $TF_EXIT_CODE -eq 0 ]; then
        log "Infrastructure deployment completed successfully"
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗" 1>&2
        echo "║                    Deployment Complete                       ║" 1>&2
        echo "╚══════════════════════════════════════════════════════════════╝" 1>&2
        echo "" 1>&2
        echo "✅ Infrastructure successfully provisioned!" 1>&2
        echo "📋 Log file: $LOG_FILE" 1>&2
        echo "" 1>&2
        
        # Verify state is non-empty before cleanup
        log "Verifying Terraform state before cleanup..."
        echo "🔍 Verifying Terraform state..." 1>&2
        final_state_check=$(terraform -chdir=$TF_ROOT_DEBUG state list 2>/dev/null | grep -v "^$" | wc -l || echo "0")
        
        if [ "$final_state_check" -eq 0 ]; then
            warning "Terraform state is empty after deployment. Keeping tfvars file for debugging."
            log "Terraform state is empty - keeping tfvars file: $TFVARS_FILE"
            echo "⚠️  Warning: Terraform state is empty - keeping tfvars file for debugging" 1>&2
        else
            log "Terraform state verified: $final_state_check resource(s) managed"
            echo "✅ Terraform state verified: $final_state_check resource(s) managed" 1>&2
            
            # Show verification commands
            echo "Verification commands:" 1>&2
            echo "  terraform state list          # List all managed resources" 1>&2
            if [ -n "$vms" ]; then
                echo "  qm list                        # List VMs in Proxmox" 1>&2
            fi
            echo "" 1>&2
            
            echo "Next steps:" 1>&2
            echo "  - Verify resources in Proxmox web interface" 1>&2
            echo "  - Check VMs, LXC containers, and backup jobs" 1>&2
            echo "  - Verify storage and networking configurations" 1>&2
            echo "" 1>&2
            echo "🔄 Rerun commands (from any directory, using absolute path):" 1>&2
            echo "  cd \"$REPO_ROOT\" && terraform plan -var-file=\"$TFVARS_FILE\"" 1>&2
            echo "  cd \"$REPO_ROOT\" && terraform apply -var-file=\"$TFVARS_FILE\" -auto-approve" 1>&2
            echo "" 1>&2
            echo "📋 Persistent tfvars file (absolute path): $TFVARS_FILE" 1>&2
            
            # Keep tfvars file with secure permissions (contains secrets but needed for reruns)
            chmod 600 "$TFVARS_FILE" 2>/dev/null || true
            log "Tfvars file kept with secure permissions (contains sensitive data): $TFVARS_FILE"
            echo "⚠️  Tfvars file contains sensitive data. Keep it secure (chmod 600)." 1>&2
        fi
    else
        log "Terraform deployment failed. Keeping tfvars file for debugging: $TFVARS_FILE"
        error_exit "Infrastructure deployment failed. Check log: $LOG_FILE"
    fi
else
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗" 1>&2
    echo "║                    Deployment Cancelled                     ║" 1>&2
    echo "╚══════════════════════════════════════════════════════════════╝" 1>&2
    echo "" 1>&2
    echo "📋 Configuration saved. Run these commands when ready (from any directory):" 1>&2
    echo "  cd \"$REPO_ROOT\" && terraform plan -var-file=\"$TFVARS_FILE\"" 1>&2
    echo "  cd \"$REPO_ROOT\" && terraform apply -var-file=\"$TFVARS_FILE\" -auto-approve" 1>&2
    echo "" 1>&2
    echo "📋 Persistent tfvars location (absolute path): $TFVARS_FILE" 1>&2
    if [ -f "$REPO_ROOT/.thinkdeploy_last_tfvars" ]; then
        LAST_TFVARS=$(cat "$REPO_ROOT/.thinkdeploy_last_tfvars" 2>/dev/null || echo "")
        if [ -n "$LAST_TFVARS" ] && [ "$LAST_TFVARS" != "$TFVARS_FILE" ]; then
            echo "ℹ️  Previous tfvars file: $LAST_TFVARS" 1>&2
        fi
    fi
    echo "📋 Last tfvars pointer: $REPO_ROOT/.thinkdeploy_last_tfvars" 1>&2
    echo "" 1>&2
    echo "📋 Log file: $LOG_FILE" 1>&2
fi

log "Script execution completed"

# Final summary with rerun commands
if [ -f "${TFVARS_FILE:-}" ]; then
    echo "" 1>&2
    echo "╔══════════════════════════════════════════════════════════════╗" 1>&2
    echo "║                    Deployment Summary                        ║" 1>&2
    echo "╚══════════════════════════════════════════════════════════════╝" 1>&2
    echo "" 1>&2
    echo "📋 Persistent tfvars file: $TFVARS_FILE" 1>&2
    echo "📋 Last tfvars pointer: $REPO_ROOT/.thinkdeploy_last_tfvars" 1>&2
    echo "" 1>&2
    echo "🔄 Rerun commands (from any directory, using absolute path):" 1>&2
    echo "  cd \"$REPO_ROOT\" && terraform plan -var-file=\"$TFVARS_FILE\"" 1>&2
    echo "  cd \"$REPO_ROOT\" && terraform apply -var-file=\"$TFVARS_FILE\" -auto-approve" 1>&2
    echo "" 1>&2
    log "Tfvars file location: $TFVARS_FILE (logged for reference)"
fi
