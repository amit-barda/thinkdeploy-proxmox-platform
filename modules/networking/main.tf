# Networking management using pvesh CLI
resource "null_resource" "bridge" {
  for_each = var.bridges

  triggers = {
    bridge_name = each.key
    iface       = each.value.iface
    stp         = each.value.stp
    mtu         = each.value.mtu
    pm_ssh_host = var.pm_ssh_host
    pm_ssh_user = var.pm_ssh_user
    pm_ssh_key  = var.pm_ssh_private_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Detect node name from SSH host (use hostname if SSH host is IP, otherwise use hostname)
      NODE_NAME=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "hostname" 2>/dev/null || echo "localhost")
      
      # Create Linux bridge
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh create /nodes/$NODE_NAME/network --iface ${self.triggers.bridge_name} --type bridge --bridge_ports ${self.triggers.iface} --stp ${self.triggers.stp} --mtu ${self.triggers.mtu}" 2>&1 || echo "Bridge may already exist"
    EOT
  }
}

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
      # Detect node name from SSH host
      NODE_NAME=$(ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "hostname" 2>/dev/null || echo "localhost")
      
      # Configure VLAN
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh create /nodes/$NODE_NAME/network --iface ${self.triggers.bridge}.${self.triggers.vlan_id} --type vlan --bridge ${self.triggers.bridge} --tag ${self.triggers.vlan_id}" 2>&1 || echo "VLAN may already exist"
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
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh create /nodes/$NODE_NAME/firewall/rules --action ${self.triggers.action} --source ${self.triggers.source} --dest ${self.triggers.dest} --proto ${self.triggers.proto} --dport ${self.triggers.dport}" 2>&1 || echo "Rule may already exist"
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
      ssh -o StrictHostKeyChecking=no -i "${self.triggers.pm_ssh_key}" "${self.triggers.pm_ssh_user}@${self.triggers.pm_ssh_host}" \
        "pvesh create /nodes/$NODE_NAME/network --iface ${self.triggers.bond_name} --type bond --bond_slaves ${self.triggers.interfaces} --bond_mode ${self.triggers.mode}" 2>&1 || echo "Bond may already exist"
    EOT
  }
}
