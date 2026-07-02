###############################################################################
# VyOS router — created FIRST. The nodes wait on time_sleep.router_ready.
###############################################################################

locals {
  vyos_user_data = templatefile("${path.module}/cloud-init/vyos-router.yaml.tftpl", {
    hostname      = var.vyos_name
    name_servers  = var.name_servers
    password_hash = var.router_password_hash
    # Bootstrap reachability for Ansible. cc_vyos authorizes these on the default
    # 'vyos' user: your mac key + the v2e mesh key + the ansible mesh key. So the
    # router comes up reachable as `vyos@10.1.1.1` by key (from control, by either
    # mesh) and over the WAN (from your mac). Phase-2 Ansible logs in here and
    # owns the rest of the router config — including creating the v2e/ansible
    # login users and retiring 'vyos'. Terraform does NOT do that config.
    admin_keys = compact([
      trimspace(var.workstation_public_key),
      local.meshes["primary"].public,
      local.meshes["ansible"].public,
    ])
    wan_address  = var.wan_address
    wan_gateway  = var.wan_gateway
    wan_iface    = var.vyos_wan_interface
    lan_iface    = var.vyos_lan_interface
    vlans        = local.vlans
    lan_supernet = var.lan_supernet

    firewall_enabled             = var.firewall_enabled
    trusted_mgmt_sources         = var.trusted_mgmt_sources
    agent_egress_restricted      = var.agent_egress_restricted
    agent_egress_allow_tcp_ports = var.agent_egress_allow_tcp_ports
    control_ip                   = local.control_ip
    control_vlan                 = local.subnets.control.vlan
    control_subnet               = "${var.network_prefix}.${local.subnets.control.octet}.0/${var.subnet_mask}"
    services_subnet              = "${var.network_prefix}.${local.subnets.services.octet}.0/${var.subnet_mask}"
    agent_subnet                 = "${var.network_prefix}.${local.subnets.agent.octet}.0/${var.subnet_mask}"
    infra_subnet                 = "${var.network_prefix}.${local.subnets.mgmt.octet}.0/${var.subnet_mask}"
    infra_ip                     = local.node_ip["infra"]

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
  tags      = sort([local.tag_project, "vyos", local.vyos_host, "terraform"])

  # Hard-stop (not graceful shutdown) on destroy — consistent teardown for all VMs.
  stop_on_destroy = true

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
