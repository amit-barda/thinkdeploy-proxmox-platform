# Verification Commands

## After Deployment - Verify Resources Were Created

### 1. Verify VMs Were Created

```bash
# List all VMs on a node
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "qm list"

# Check specific VM
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "qm status <vmid>"

# Via pvesh
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /nodes/<node>/qemu/<vmid>"
```

**Expected Output**: VM should appear in `qm list` with the configured vmid, cores, and memory.

---

### 2. Verify API Tokens Were Created

```bash
# List all tokens for a user
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pveum user token list <user>@pam"

# Get specific token details
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /access/users/<user>@pam/token/<tokenid>"

# Via pvesh
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /access/users/<user>@pam/token/<tokenid>"
```

**Expected Output**: Token should appear in the list with the configured tokenid and expiration.

---

### 3. Verify LXC Containers Were Created

```bash
# List all LXC containers
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pct list"

# Check specific container
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pct status <ctid>"

# Via pvesh
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /nodes/<node>/lxc/<ctid>"
```

**Expected Output**: Container should appear in `pct list` with the configured ctid.

---

### 4. Verify Cluster Status

```bash
# Check cluster status
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvecm status"

# List cluster nodes
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvecm nodes"

# Check if cluster exists
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvecm status 2>&1 | grep -q 'Cluster information' && echo 'Cluster exists' || echo 'No cluster'"
```

**Expected Output**: If cluster was created, `pvecm status` should show cluster information.

---

### 5. Verify Storage Was Added

```bash
# List all storage
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /storage"

# Check specific storage
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /storage/<storage-name>"

# List storage on a node
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /nodes/<node>/storage"
```

**Expected Output**: Storage should appear in the storage list.

---

### 6. Verify Backup Jobs Were Created

```bash
# List all backup jobs
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /cluster/backup"

# Check specific backup job
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /cluster/backup/<job-id>"
```

**Expected Output**: Backup job should appear in the list with configured schedule and VMs.

---

### 7. Verify Terraform State

```bash
# List all resources in Terraform state
terraform state list

# Show specific resource
terraform state show module.vm["<vm-name>"].null_resource.vm[0]

# Show all VMs
terraform state list | grep "module.vm"

# Show all API tokens
terraform state list | grep "module.security"
```

**Expected Output**: Resources should appear in terraform state.

---

## Troubleshooting Commands

### Check Terraform Logs

```bash
# View latest setup log
ls -lt /tmp/thinkdeploy-setup-*.log | head -1 | xargs cat

# View terraform output
terraform output

# Check terraform plan (dry run)
terraform plan -var-file=/tmp/thinkdeploy-*.tfvars.json
```

### Check Proxmox Connectivity

```bash
# Test SSH connection
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "echo 'SSH OK'"

# Test pvesh availability
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /version"

# Test node access
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /nodes"
```

### Check Resource Existence Before Creation

```bash
# Check if VMID is free
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "qm list | grep -q '^  <vmid>' && echo 'VMID in use' || echo 'VMID free'"

# Check if token exists
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pveum user token list <user>@pam | grep -q '<tokenid>' && echo 'Token exists' || echo 'Token free'"

# Check if storage exists
ssh -i ~/.ssh/id_rsa root@<proxmox-host> "pvesh get /storage/<storage-name> 2>/dev/null && echo 'Storage exists' || echo 'Storage not found'"
```

---

## Quick Verification Script

Create a file `verify_deployment.sh`:

```bash
#!/bin/bash

PROXMOX_HOST="${TF_VAR_pm_ssh_host:-localhost}"
SSH_KEY="${TF_VAR_pm_ssh_private_key_path:-~/.ssh/id_rsa}"
SSH_USER="${TF_VAR_pm_ssh_user:-root}"

echo "=== Verifying Deployment ==="
echo ""

# Check VMs
echo "Checking VMs..."
ssh -i "$SSH_KEY" "$SSH_USER@$PROXMOX_HOST" "qm list"
echo ""

# Check LXC containers
echo "Checking LXC containers..."
ssh -i "$SSH_KEY" "$SSH_USER@$PROXMOX_HOST" "pct list"
echo ""

# Check API tokens
echo "Checking API tokens..."
ssh -i "$SSH_KEY" "$SSH_USER@$PROXMOX_HOST" "pveum user token list" 2>/dev/null || echo "No tokens found or pveum not available"
echo ""

# Check cluster
echo "Checking cluster status..."
ssh -i "$SSH_KEY" "$SSH_USER@$PROXMOX_HOST" "pvecm status 2>&1 | head -5"
echo ""

# Check storage
echo "Checking storage..."
ssh -i "$SSH_KEY" "$SSH_USER@$PROXMOX_HOST" "pvesh get /storage | jq -r '.[] | .storage' 2>/dev/null || pvesh get /storage"
echo ""

# Check backup jobs
echo "Checking backup jobs..."
ssh -i "$SSH_KEY" "$SSH_USER@$PROXMOX_HOST" "pvesh get /cluster/backup 2>/dev/null || echo 'No backup jobs'"
echo ""

echo "=== Terraform State ==="
terraform state list
```

Make it executable:
```bash
chmod +x verify_deployment.sh
./verify_deployment.sh
```
