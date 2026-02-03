# ThinkDeploy Proxmox Automation Platform

**Senior Platform Engineer - Infrastructure Automation Architect**

This comprehensive Terraform-based infrastructure automation solution provides enterprise-grade management of all Proxmox VE infrastructure components. Designed for production environments with emphasis on reliability, maintainability, and operational excellence.

## Enterprise Deployment Guide

### Prerequisites
- **Terraform** >= 1.6 (auto-installed by install.sh)
- **Proxmox VE CLI** (`pvesh` command)
- **Network connectivity** to Proxmox cluster
- **Administrative privileges** on Proxmox nodes
- **Supported OS**: Linux (Debian/Ubuntu, RHEL/CentOS, Fedora), macOS

### Quick Deployment

1. **One-Command Installation:**
   ```bash
   # Clone and run automated installation
   git clone https://github.com/thinkdeploy/proxmox-platform.git
   cd thinkdeploy-proxmox-platform
   sudo ./install.sh
   ```

2. **Interactive Infrastructure Setup:**
   ```bash
   ./setup.sh
   ```
   
   The enterprise setup script provides a comprehensive menu system:
   - **Main Menu** with 6 categories
   - **Input validation** for all parameters
   - **Default values** for all options (just press Enter)
   - **Quick pre-deployment validation** with Terraform plan
   - **Comprehensive logging** to `/tmp/thinkdeploy-setup-*.log`
   - **Professional UI** with structured output

## Main Menu Options

### 1. Cluster Management
- ✅ Create cluster
- ✅ Join nodes to cluster
- ✅ Configure HA (High Availability)
- ✅ Tune Corosync
- ✅ Health checks
- ✅ Backup cluster config

### 2. Compute / VM / LXC
- ✅ Create VM
- ✅ Create LXC container
- ✅ Create VM from template (cloud-init)
- ✅ Create snapshots
- ✅ Configure hotplug (CPU/RAM)
- ✅ Configure auto-scaling
- ✅ Add tags/labels

### 3. Networking
- ✅ Create Linux bridges
- ✅ Configure VLANs
- ✅ Configure SDN
- ✅ Firewall rules
- ✅ NAT configuration
- ✅ Network bonding
- ✅ MTU optimization

### 4. Storage
- ✅ NFS storage
- ✅ iSCSI storage
- ✅ Ceph storage
- ✅ ZFS pools
- ✅ Backup storages
- ✅ Replication jobs
- ✅ Storage encryption

### 5. Backup & DR
- ✅ Create backup jobs
- ✅ Configure schedules
- ✅ Backup verification
- ✅ Restore testing
- ✅ Offsite sync
- ✅ Snapshot policies
- ✅ DR workflows

### 6. Security
- ✅ Configure RBAC
- ✅ Create API tokens
- ✅ SSH hardening
- ✅ Firewall policies
- ✅ Audit logging
- ✅ Compliance profiles

## Project Structure

```
thinkdeploy-proxmox-platform/
├─ modules/
│  ├─ cluster/          # Cluster management
│  ├─ vm/               # VM management
│  ├─ backup_job/       # Backup job management
│  ├─ storage/           # Storage management
│  ├─ networking/        # Networking management
│  └─ security/          # Security management
├─ main.tf               # Root module configuration
├─ variables.tf          # Input variables
├─ outputs.tf            # Output values
├─ providers.tf          # Provider configuration
├─ install.sh            # Installation script
├─ setup.sh              # Interactive setup script
└─ README.md             # This file
```

## Usage Example

```bash
# 1. Install
sudo ./install.sh

# 2. Run interactive setup
./setup.sh

# Main menu appears:
# 1. Cluster Management
# 2. Compute / VM / LXC
# 3. Networking
# 4. Storage
# 5. Backup & DR
# 6. Security
# 7. Deploy All
# 8. Exit

# Select option 2 (Compute)
# Then select:
# 1. Create VM
# Enter details (or press Enter for defaults)
# VM created automatically!

# Select option 5 (Backup)
# Configure backup job
# Backup scheduled automatically!

# Select option 7 (Deploy All)
# Everything deploys via Terraform
```

## Configuration Examples

### VM with Cloud-Init
```bash
# In setup.sh menu:
# 2. Compute / VM / LXC
# 3. Create VM from template (cloud-init)
# Enter: VM ID, template name, SSH key
# VM created with cloud-init automatically!
```

### HA Cluster
```bash
# In setup.sh menu:
# 1. Cluster Management
# 3. Configure HA
# Enter: HA group name, nodes
# HA configured automatically!
```

### NFS Storage
```bash
# In setup.sh menu:
# 4. Storage
# 1. NFS storage
# Enter: Server IP, export path, nodes
# NFS storage added to all nodes automatically!
```

## Schedule Format Examples

- `"0 2 * * *"` - Daily at 2 AM
- `"0 3 * * 0"` - Weekly on Sunday at 3 AM
- `"0 1 1 * *"` - Monthly on the 1st at 1 AM
- `"0 */6 * * *"` - Every 6 hours

## Important Notes

### Implementation Details
This project uses `pvesh` CLI commands via `null_resource` provisioners for maximum flexibility and coverage of all Proxmox features.

### Prerequisites
- `pvesh` CLI tool must be installed and configured
- Proper authentication to Proxmox API
- SSH access to Proxmox nodes
- Node names must exactly match your Proxmox node names

### Node Names
- Check node names with: `pvesh get /nodes`

### VM IDs
- Check VM IDs with: `pvesh get /cluster/resources --type vm`

### Authentication
For production, consider using API tokens instead of passwords.

## Troubleshooting

### Common Issues
1. **Node names don't match**: Verify with `pvesh get /nodes`
2. **VM IDs invalid**: Check with `pvesh get /cluster/resources --type vm`
3. **SSH connection failed**: Verify SSH key and access
4. **Schedule format**: Proxmox validates cron syntax - check logs for errors

### Validation Commands
```bash
terraform validate
terraform plan -detailed-exitcode
```

## Next Steps After Changes

1. `terraform init` - Initialize providers
2. `terraform validate` - Check syntax
3. `terraform plan` - Review changes
4. `terraform apply` - Apply configuration

---

**Status**: Production Ready | **Version**: 1.0.0 | **Proxmox Support**: 8.x+

Built with ❤️ by the ThinkDeploy team
