###############################################################################
# control / services / agent — created AFTER the router is up (time_sleep).
###############################################################################

locals {
  node_user_data = { for k, n in local.nodes : k => templatefile("${path.module}/cloud-init/node.yaml.tftpl", {
    hostname        = k
    node_users      = local.node_users[k]
    has_hub         = local.node_has_hub[k]
    package_upgrade = var.package_upgrade
    extra_packages  = var.extra_packages
    # Cloudflare tunnel connector token — only the control node gets it, and only
    # when the tunnel is enabled. "" renders the cloud-init identically to before.
    cloudflared_token = (local.cloudflare_enabled && k == "control") ? one(data.cloudflare_zero_trust_tunnel_cloudflared_token.ssh[*].token) : ""
    # Ansible bootstrap — only the control node clones the repo and runs the
    # playbook against the mesh. "" disables the block (cloud-init unchanged).
    ansible_repo_url  = k == "control" ? var.ansible_repo_url : ""
    ansible_repo_ref  = var.ansible_repo_ref
    ansible_playbook  = var.ansible_playbook
    ansible_inventory = var.ansible_inventory
    # The bootstrap runs as the dedicated ansible account (a hub user on control),
    # so it reuses that mesh's SSH key/config to reach every node + the router.
    ansible_user = var.ansible_user
  }) }
}

resource "proxmox_virtual_environment_file" "node_user_data" {
  for_each = local.nodes

  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.node_name

  source_raw {
    data      = local.node_user_data[each.key]
    file_name = "v2e-v3-${each.key}-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes

  depends_on = [time_sleep.router_ready]

  name      = each.key
  vm_id     = each.value.vm_id
  node_name = var.node_name
  tags      = ["v2e-v3", each.value.role, "terraform"]

  agent {
    enabled = false
  }

  clone {
    vm_id = each.value.template_id
    full  = true
  }

  cpu {
    cores = var.node_cores
    type  = "host"
  }

  memory {
    dedicated = var.node_memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.node_disk_size
  }

  # Single access port tagged into this node's VLAN.
  network_device {
    bridge  = var.lan_bridge
    model   = "virtio"
    vlan_id = each.value.vlan
  }

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = local.node_ip_cidr[each.key]
        gateway = local.node_gateway[each.key]
      }
    }

    dns {
      servers = var.name_servers
    }

    user_data_file_id = proxmox_virtual_environment_file.node_user_data[each.key].id
  }
}
