###############################################################################
# VyOS router — created FIRST. The nodes wait on time_sleep.router_ready.
###############################################################################

locals {
  vyos_user_data = templatefile("${path.module}/cloud-init/vyos-router.yaml.tftpl", {
    hostname      = var.vyos_name
    name_servers  = var.name_servers
    password_hash = var.router_password_hash
    # Authorized via top-level ssh_authorized_keys (the cc_vyos module applies these to
    # the default 'vyos' user): your mac key + the v2e mesh key, so the control node
    # (which holds the v2e private key) can `ssh vyos@10.1.1.1` by key.
    admin_keys = compact([
      trimspace(var.workstation_public_key),
      local.meshes["primary"].public,
    ])
    wan_address  = var.wan_address
    wan_gateway  = var.wan_gateway
    wan_iface    = var.vyos_wan_interface
    lan_iface    = var.vyos_lan_interface
    vlans        = local.vlans
    lan_supernet = var.lan_supernet
    port_forwards = [
      {
        rule        = 10
        description = "DNAT to control node SSH"
        protocol    = "tcp"
        wan_port    = var.control_ssh_wan_port
        lan_address = local.control_ip
        lan_port    = 22
      }
    ]
    extra_config_commands = var.extra_vyos_commands
  })
}

resource "proxmox_virtual_environment_file" "vyos_user_data" {
  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.node_name

  source_raw {
    data      = local.vyos_user_data
    file_name = "${var.vyos_name}-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "vyos" {
  name      = var.vyos_name
  vm_id     = var.vyos_vmid
  node_name = var.node_name
  tags      = ["v2e-v3", "vyos", "router", "terraform"]

  # VyOS template has no running guest agent — don't let Terraform wait on it.
  agent {
    enabled = false
  }

  clone {
    vm_id = var.vyos_template_id
    full  = true
  }

  cpu {
    cores = var.vyos_cores
    type  = "host"
  }

  memory {
    dedicated = var.vyos_memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.vyos_disk_size
  }

  # net0 -> eth0 : WAN
  network_device {
    bridge = var.wan_bridge
    model  = "virtio"
  }

  # net1 -> eth1 : LAN trunk (no vlan_id; carries all VLAN tags)
  network_device {
    bridge = var.lan_bridge
    model  = "virtio"
    trunks = local.trunk_string
  }

  initialization {
    datastore_id      = var.datastore_id
    user_data_file_id = proxmox_virtual_environment_file.vyos_user_data.id
  }
}

# Gate the nodes on the router booting + applying routing.
resource "time_sleep" "router_ready" {
  depends_on      = [proxmox_virtual_environment_vm.vyos]
  create_duration = var.router_boot_wait

  triggers = {
    router_id = proxmox_virtual_environment_vm.vyos.id
  }
}
