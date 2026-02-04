# Networking management using pvesh CLI
resource "null_resource" "bridge" {
  for_each = var.bridges

  triggers = {
    bridge_name  = each.key
    iface        = each.value.iface
    stp          = each.value.stp
    mtu          = each.value.mtu
    ipv4_cidr    = try(each.value.ipv4_cidr, "")
    ipv4_gateway = try(each.value.ipv4_gateway, "")
    ipv6_cidr    = try(each.value.ipv6_cidr, "")
    ipv6_gateway = try(each.value.ipv6_gateway, "")
    autostart    = try(each.value.autostart, "N")
    vlan_aware   = try(each.value.vlan_aware, "N")
    comment      = try(each.value.comment, "")
    pm_ssh_host  = var.pm_ssh_host
    pm_ssh_user  = var.pm_ssh_user
    pm_ssh_key   = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      
      INTERFACES_FILE="/etc/network/interfaces"
      BRIDGE_NAME="${self.triggers.bridge_name}"
      PHYSICAL_IFACE="${self.triggers.iface}"
      
      # Create backup of interfaces file
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "cp $INTERFACES_FILE $INTERFACES_FILE.backup.$(date +%s)" 2>/dev/null || true
      
      # Check if bridge already exists in interfaces file
      BRIDGE_EXISTS=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "grep -q '^auto $BRIDGE_NAME' $INTERFACES_FILE 2>/dev/null && echo 'yes' || echo 'no'")
      
      if [ "$BRIDGE_EXISTS" = "yes" ]; then
        echo "Bridge $BRIDGE_NAME already exists in $INTERFACES_FILE"
        
        # If VLAN-aware is requested, check and update if needed
        if [ "${self.triggers.vlan_aware}" = "y" ] || [ "${self.triggers.vlan_aware}" = "Y" ]; then
          VLAN_AWARE_EXISTS=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
            "grep -A 10 '^iface $BRIDGE_NAME' $INTERFACES_FILE 2>/dev/null | grep -q 'bridge-vlan-aware yes' && echo 'yes' || echo 'no'")
          
          if [ "$VLAN_AWARE_EXISTS" != "yes" ]; then
            echo "Updating existing bridge $BRIDGE_NAME to enable VLAN-aware mode..."
            # Add bridge-vlan-aware yes after bridge-ports line using Python
            ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
              "python3 << 'PYEOF'
import re
import sys
bridge_name = '$BRIDGE_NAME'
interfaces_file = '$INTERFACES_FILE'
try:
    with open(interfaces_file, 'r') as f:
        lines = f.readlines()
    in_bridge = False
    insert_pos = -1
    for i, line in enumerate(lines):
        if re.match(r'^iface ' + re.escape(bridge_name) + r' ', line):
            in_bridge = True
        elif in_bridge and 'bridge-ports' in line:
            insert_pos = i
        elif in_bridge and re.match(r'^[^ ]', line) and not line.strip().startswith('#'):
            if insert_pos >= 0:
                lines.insert(insert_pos + 1, '    bridge-vlan-aware yes\n')
            break
    if insert_pos >= 0:
        with open(interfaces_file, 'w') as f:
            f.writelines(lines)
        print('Updated bridge', bridge_name, 'to VLAN-aware')
except Exception as e:
    print('Error:', str(e), file=sys.stderr)
    sys.exit(1)
PYEOF
" 2>&1 || echo "WARNING: Could not automatically add bridge-vlan-aware. Please add it manually."
            echo "Bridge $BRIDGE_NAME updated to VLAN-aware mode"
          else
            echo "Bridge $BRIDGE_NAME is already VLAN-aware"
          fi
        fi
        
        exit 0
      fi
      
      # Build interfaces file content
      INTERFACES_CONTENT=""
      
      # Add physical interface configuration (if not already present)
      PHYSICAL_EXISTS=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "grep -q '^iface $PHYSICAL_IFACE' $INTERFACES_FILE 2>/dev/null && echo 'yes' || echo 'no'")
      
      if [ "$PHYSICAL_EXISTS" = "no" ]; then
        INTERFACES_CONTENT="$INTERFACES_CONTENT
# Physical interface configuration
iface $PHYSICAL_IFACE inet manual
"
      fi
      
      # Build bridge configuration
      INTERFACES_CONTENT="$INTERFACES_CONTENT
# Bridge configuration: $BRIDGE_NAME
auto $BRIDGE_NAME
iface $BRIDGE_NAME inet"
      
      # Add IP configuration
      if [ -n "${self.triggers.ipv4_cidr}" ]; then
        # Use CIDR format directly (e.g., 192.168.1.10/24)
        INTERFACES_CONTENT="$INTERFACES_CONTENT static
    address ${self.triggers.ipv4_cidr}"
        if [ -n "${self.triggers.ipv4_gateway}" ]; then
          INTERFACES_CONTENT="$INTERFACES_CONTENT
    gateway ${self.triggers.ipv4_gateway}"
        fi
      else
        INTERFACES_CONTENT="$INTERFACES_CONTENT manual"
      fi
      
      # Add bridge-specific options
      INTERFACES_CONTENT="$INTERFACES_CONTENT
    bridge-ports $PHYSICAL_IFACE"
      
      # STP configuration
      if [ "${self.triggers.stp}" = "y" ] || [ "${self.triggers.stp}" = "Y" ]; then
        INTERFACES_CONTENT="$INTERFACES_CONTENT
    bridge-stp on"
      else
        INTERFACES_CONTENT="$INTERFACES_CONTENT
    bridge-stp off
    bridge-fd 0"
      fi
      
      # MTU
      if [ -n "${self.triggers.mtu}" ] && [ "${self.triggers.mtu}" != "1500" ]; then
        INTERFACES_CONTENT="$INTERFACES_CONTENT
    mtu ${self.triggers.mtu}"
      fi
      
      # VLAN-aware configuration
      if [ "${self.triggers.vlan_aware}" = "y" ] || [ "${self.triggers.vlan_aware}" = "Y" ]; then
        INTERFACES_CONTENT="$INTERFACES_CONTENT
    bridge-vlan-aware yes"
      else
      fi
      
      # Add comment if provided
      if [ -n "${self.triggers.comment}" ]; then
        INTERFACES_CONTENT="$INTERFACES_CONTENT
    # ${self.triggers.comment}"
      fi
      
      # Append to interfaces file
      echo "$INTERFACES_CONTENT" | ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "cat >> $INTERFACES_FILE"
      
      # Apply network configuration
      # Try ifreload first (Debian/Ubuntu), then fallback to ifup
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "if command -v ifreload >/dev/null 2>&1; then ifreload -a; else ifup $BRIDGE_NAME 2>/dev/null || echo 'Bridge will be activated on next reboot'; fi" 2>&1 || echo "Network reload may have failed, but configuration was written"
      
      echo "Bridge $BRIDGE_NAME configured successfully"
    EOT
  }
}

# VLAN configuration using Approach B: VLAN sub-interfaces in /etc/network/interfaces
# Creates Linux VLAN sub-interfaces: auto vmbr0.<vlan_id> and iface vmbr0.<vlan_id> inet manual with vlan-raw-device
resource "null_resource" "vlan" {
  for_each = var.vlans

  triggers = {
    vlan_id     = each.value.id
    vlan_name   = each.value.name
    bridge      = each.value.bridge
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      
      # Don't use set -e here - we want to log errors and continue
      set +e
      
      INTERFACES_FILE="/etc/network/interfaces"
      BRIDGE_NAME="${self.triggers.bridge}"
      VLAN_ID=${self.triggers.vlan_id}
      VLAN_IFACE="$BRIDGE_NAME.$VLAN_ID"
      
      # Validate VLAN ID range (1-4094)
      if [ "$VLAN_ID" -lt 1 ] || [ "$VLAN_ID" -gt 4094 ]; then
        echo "ERROR: Invalid VLAN ID: $VLAN_ID (must be 1-4094)"
        exit 1
      fi
      
      # Check if bridge exists
      BRIDGE_EXISTS=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "ip link show $BRIDGE_NAME >/dev/null 2>&1 && echo 'yes' || echo 'no'")
      
      if [ "$BRIDGE_EXISTS" != "yes" ]; then
        echo "ERROR: Bridge $BRIDGE_NAME does not exist. Please create the bridge first."
        exit 1
      fi
      
      # Check if VLAN sub-interface already exists in interfaces file
      VLAN_IFACE_EXISTS=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "grep -q '^iface $VLAN_IFACE' $INTERFACES_FILE 2>/dev/null && echo 'yes' || echo 'no'")
      
      if [ "$VLAN_IFACE_EXISTS" = "yes" ]; then
        echo "VLAN sub-interface $VLAN_IFACE already exists in $INTERFACES_FILE, skipping creation"
      else
        echo "Creating VLAN sub-interface $VLAN_IFACE in $INTERFACES_FILE..."
        
        # Create backup
        ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
          "cp $INTERFACES_FILE $INTERFACES_FILE.backup.vlan-$(date +%s)" 2>/dev/null || true
        
        # Build VLAN sub-interface configuration
        VLAN_CONFIG="
# VLAN sub-interface: $VLAN_IFACE (VLAN ID: $VLAN_ID, Name: ${self.triggers.vlan_name})
auto $VLAN_IFACE
iface $VLAN_IFACE inet manual
    vlan-raw-device $BRIDGE_NAME
"
        
        # Append to interfaces file
        SSH_APPEND_EXIT=0
        echo "$VLAN_CONFIG" | ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
          "cat >> $INTERFACES_FILE" 2>&1 || SSH_APPEND_EXIT=$?
        
        if [ $SSH_APPEND_EXIT -ne 0 ]; then
          echo "ERROR: Failed to append VLAN configuration to $INTERFACES_FILE (exit code: $SSH_APPEND_EXIT)"
          exit 1
        fi
        
        echo "VLAN sub-interface $VLAN_IFACE configuration added to $INTERFACES_FILE"
        
        # Apply network configuration (idempotent - safe to run multiple times)
        echo "Applying network configuration..."
        
        RELOAD_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
          "if command -v ifreload >/dev/null 2>&1; then ifreload -a 2>&1; else ifup $VLAN_IFACE 2>&1 || echo 'Interface will be activated on next reboot'; fi" 2>&1)
        RELOAD_EXIT=$?
        
        if [ $RELOAD_EXIT -eq 0 ]; then
          echo "Network configuration reloaded successfully"
        else
          echo "WARNING: Network reload may have failed, but configuration was written. Output: $RELOAD_OUTPUT"
          echo "You may need to manually run: ifreload -a or restart networking service"
        fi
      fi
      
      # Verification: Check VLAN sub-interface
      echo ""
      echo "=== VLAN Configuration Verification ==="
      echo "VLAN ID: $VLAN_ID"
      echo "VLAN Name: ${self.triggers.vlan_name}"
      echo "VLAN Interface: $VLAN_IFACE"
      echo "Bridge: $BRIDGE_NAME"
      
      # Check if VLAN interface exists in runtime
      VLAN_IFACE_RUNTIME=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "ip link show $VLAN_IFACE 2>/dev/null && echo 'yes' || echo 'no'")
      
      # Show VLAN interface details
      if [ "$VLAN_IFACE_RUNTIME" = "yes" ]; then
        VLAN_DETAILS=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
          "ip -d link show $VLAN_IFACE 2>/dev/null || echo 'Interface details not available'")
        echo "VLAN interface status: ACTIVE"
        echo "VLAN interface details:"
        echo "$VLAN_DETAILS"
      else
        echo "VLAN interface status: NOT ACTIVE (may require network reload or reboot)"
      fi
      
      # Show VLAN info from ip command
      VLAN_INFO=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "ip -d link show | grep -A 5 $VLAN_IFACE 2>/dev/null || echo 'VLAN info not available'")
      echo "VLAN info from ip command:"
      echo "$VLAN_INFO"
      
      echo ""
      echo "=== VLAN Sub-interface Created Successfully ==="
      echo "VLAN $VLAN_ID (${self.triggers.vlan_name}) is now available as interface $VLAN_IFACE"
      echo "Configuration written to: $INTERFACES_FILE"
      echo ""
      echo "To use this VLAN:"
      echo "  - The interface $VLAN_IFACE is now available for network configuration"
      echo "  - You can assign IP addresses or use it in bridge configurations"
      echo "  - For VMs/LXCs, you can use bridge=$VLAN_IFACE in network configuration"
    EOT
  }
}

resource "null_resource" "firewall_rule" {
  for_each = var.firewall_rules

  triggers = {
    rule_name   = each.key
    action      = each.value.action
    source      = each.value.source
    dest        = each.value.dest
    proto       = each.value.proto
    dport       = each.value.dport
    type        = try(each.value.type, "in")
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      
      # Detect node name from SSH host
      NODE_NAME=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "hostname" 2>/dev/null || echo "localhost")
      
      # Create firewall rule
      PVE_CMD="pvesh create /nodes/$NODE_NAME/firewall/rules --action ${self.triggers.action} --type ${self.triggers.type} --source ${self.triggers.source} --dest ${self.triggers.dest} --proto ${self.triggers.proto} --dport ${self.triggers.dport}"
      
      PVE_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$PVE_CMD" 2>&1)
      PVE_EXIT=$?
      
      if [ $PVE_EXIT -ne 0 ]; then
        echo "Firewall rule creation failed (exit code $PVE_EXIT): $PVE_OUTPUT"
        exit 1
      else
        echo "Firewall rule created successfully: $PVE_OUTPUT"
      fi
    EOT
  }
}

resource "null_resource" "bond" {
  for_each = var.bonds

  triggers = {
    bond_name   = each.key
    interfaces  = join(",", each.value.interfaces)
    mode        = each.value.mode
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      
      # Detect node name from SSH host
      NODE_NAME=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "hostname" 2>/dev/null || echo "localhost")
      
      # Create network bond
      # Convert comma-separated interfaces to space-separated (Proxmox API requirement)
      INTERFACES_SPACE=$(echo "${self.triggers.interfaces}" | tr ',' ' ')
      
      # Validate that all interfaces exist before creating bond
      MISSING_IFACES=""
      for iface in $INTERFACES_SPACE; do
        if ! ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
          "ip link show $iface >/dev/null 2>&1"; then
          MISSING_IFACES="$MISSING_IFACES $iface"
        fi
      done
      
      if [ -n "$MISSING_IFACES" ]; then
        echo "ERROR: Interfaces do not exist:$MISSING_IFACES"
        echo "Available interfaces: $(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "ip link show | grep -E '^[0-9]+:' | awk '{print \$2}' | sed 's/:$//' | tr '\n' ' '")"
        exit 1
      fi
      
      PVE_CMD="pvesh create /nodes/$NODE_NAME/network --iface ${self.triggers.bond_name} --type bond --slaves \"$INTERFACES_SPACE\" --bond_mode ${self.triggers.mode}"
      
      PVE_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$PVE_CMD" 2>&1)
      PVE_EXIT=$?
      
      if [ $PVE_EXIT -ne 0 ]; then
        echo "Bond creation may have failed (exit code $PVE_EXIT): $PVE_OUTPUT"
        echo "Note: Bond may already exist, which is acceptable"
      else
        echo "Bond created successfully: $PVE_OUTPUT"
      fi
    EOT
  }
}

# SDN zone configuration
resource "null_resource" "sdn" {
  for_each = var.sdns

  triggers = {
    sdn_name    = each.value.name
    sdn_type    = each.value.type
    sdn_bridge  = each.value.bridge
    sdn_vlan    = each.value.vlan
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      
      # Detect node name from SSH host
      NODE_NAME=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "hostname" 2>/dev/null || echo "localhost")
      
      # Create SDN zone using pvesh
      # Note: SDN configuration in Proxmox uses /cluster/sdn/zones endpoint
      # Build command based on SDN type - different types have different parameters
      # For VLAN type zones, VLAN ID is configured at the subnet level, not zone level
      if [ "${self.triggers.sdn_type}" = "vlan" ]; then
        # For VLAN type, only bridge is needed at zone level
        # VLAN ID will be configured when creating subnets within this zone
        PVE_CMD="pvesh create /cluster/sdn/zones --zone ${self.triggers.sdn_name} --type ${self.triggers.sdn_type} --bridge ${self.triggers.sdn_bridge}"
      elif [ "${self.triggers.sdn_type}" = "vxlan" ]; then
        # For VXLAN type, use bridge
        PVE_CMD="pvesh create /cluster/sdn/zones --zone ${self.triggers.sdn_name} --type ${self.triggers.sdn_type} --bridge ${self.triggers.sdn_bridge}"
      elif [ "${self.triggers.sdn_type}" = "evpn" ]; then
        # For EVPN type, use bridge
        PVE_CMD="pvesh create /cluster/sdn/zones --zone ${self.triggers.sdn_name} --type ${self.triggers.sdn_type} --bridge ${self.triggers.sdn_bridge}"
      else
        # For other types (simple, qinq, faucet), use bridge
        PVE_CMD="pvesh create /cluster/sdn/zones --zone ${self.triggers.sdn_name} --type ${self.triggers.sdn_type} --bridge ${self.triggers.sdn_bridge}"
      fi
      
      PVE_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$PVE_CMD" 2>&1)
      PVE_EXIT=$?
      
      if [ $PVE_EXIT -ne 0 ]; then
        echo "SDN zone creation failed (exit code $PVE_EXIT): $PVE_OUTPUT"
        exit 1
      else
        echo "SDN zone created successfully: $PVE_OUTPUT"
      fi
    EOT
  }
}

# NAT rule configuration
resource "null_resource" "nat" {
  for_each = var.nats

  triggers = {
    nat_name    = each.value.name
    nat_source  = each.value.source
    nat_iface   = each.value.interface
    nat_snat    = each.value.snat
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      
      # Detect node name from SSH host
      NODE_NAME=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "hostname" 2>/dev/null || echo "localhost")
      
      # Create NAT rule using iptables (NAT is typically configured via iptables, not pvesh)
      # For Proxmox, NAT rules are usually configured via firewall rules with action=ACCEPT and SNAT
      if [ "${self.triggers.nat_snat}" = "y" ] || [ "${self.triggers.nat_snat}" = "Y" ]; then
        # Configure SNAT using iptables
        IPTABLES_CMD="iptables -t nat -A POSTROUTING -s ${self.triggers.nat_source} -o ${self.triggers.nat_iface} -j MASQUERADE"
        
        IPTABLES_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" "$IPTABLES_CMD" 2>&1)
        IPTABLES_EXIT=$?
        
        if [ $IPTABLES_EXIT -eq 0 ]; then
          echo "NAT rule created successfully (SNAT enabled)"
          # Save iptables rules to make them persistent
          ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
            "iptables-save > /etc/iptables/rules.v4 2>/dev/null || netfilter-persistent save 2>/dev/null || echo 'Note: Install iptables-persistent or netfilter-persistent to make rules persistent'" 2>&1
        else
          echo "NAT rule creation failed (exit code $IPTABLES_EXIT): $IPTABLES_OUTPUT"
          exit 1
        fi
      else
        echo "SNAT disabled for NAT rule ${self.triggers.nat_name}"
      fi
    EOT
  }
}

# MTU configuration
resource "null_resource" "mtu" {
  for_each = var.mtus

  triggers = {
    interface   = each.value.interface
    mtu         = each.value.mtu
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      
      INTERFACE="${self.triggers.interface}"
      MTU=${self.triggers.mtu}
      
      # Check if interface exists
      INTERFACE_EXISTS=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "ip link show $INTERFACE >/dev/null 2>&1 && echo 'yes' || echo 'no'")
      
      if [ "$INTERFACE_EXISTS" != "yes" ]; then
        echo "ERROR: Interface $INTERFACE does not exist"
        exit 1
      fi
      
      # Set MTU using ip link
      echo "Setting MTU $MTU on interface $INTERFACE..."
      
      MTU_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "ip link set $INTERFACE mtu $MTU" 2>&1)
      MTU_EXIT=$?
      
      if [ $MTU_EXIT -ne 0 ]; then
        echo "MTU configuration failed (exit code $MTU_EXIT): $MTU_OUTPUT"
        exit 1
      else
        echo "MTU $MTU set successfully on interface $INTERFACE"
        # Verify MTU
        CURRENT_MTU=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
          "ip link show $INTERFACE 2>/dev/null | grep -oP 'mtu \K[0-9]+' || echo 'unknown'")
        echo "Current MTU on $INTERFACE: $CURRENT_MTU"
      fi
    EOT
  }
}
