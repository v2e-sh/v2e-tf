###############################################################################
# control / services / agent — created AFTER the router is up (time_sleep).
###############################################################################

locals {
  node_user_data = { for k, n in local.nodes : k => templatefile("${path.module}/cloud-init/node.yaml.tftpl", {
    hostname        = k
    node_users      = local.node_users[k]
    has_hub         = local.node_has_hub[k]
    package_upgrade = var.package_upgrade
    # Cloudflare tunnel connector token — only the control node gets it, and only
    # when the tunnel is enabled. "" renders the cloud-init identically to before.
    cloudflared_token = (local.cloudflare_enabled && k == "control") ? one(data.cloudflare_zero_trust_tunnel_cloudflared_token.ssh[*].token) : ""
    # Ansible bootstrap — only the control node clones the repo and runs the
    # playbook against the mesh. "" disables the block (cloud-init unchanged).
    ansible_repo_url  = k == "control" ? var.ansible_repo_url : ""
    ansible_version   = var.ansible_version
    ansible_playbook  = var.ansible_playbook
    ansible_inventory = var.ansible_inventory
    # The bootstrap runs as the dedicated ansible account (a hub user on control),
    # so it reuses that mesh's SSH key/config to reach every node + the router.
    ansible_user = var.ansible_user
    # Ansible Vault password — seeded only on control (the bootstrap runner) and
    # only when set; written to /home/<ansible_user>/.vault_pass. "" = not seeded.
    ansible_vault_password = k == "control" ? var.ansible_vault_password : ""
    # SOPS — only control gets the encrypted secrets + age key, and only when set.
    # file() reads at plan time; the gate short-circuits so it's never called for
    # other nodes or when the path is "". "" renders the SOPS cloud-init blocks
    # empty — byte-identical to the no-SOPS case.
    sops_secrets = (k == "control" && var.sops_secrets_file != "") ? file(var.sops_secrets_file) : ""
    sops_age_key = (k == "control" && var.sops_age_key_file != "") ? file(var.sops_age_key_file) : ""
  }) }
}

# Both-or-neither: a secrets file with no age key can't be decrypted on control, and
# an age key with no secrets is pointless. Warn (don't block) on a half-config — same
# style as the Cloudflare consistency check.
check "sops_vars_consistent" {
  assert {
    condition = (
      (var.sops_secrets_file != "" && var.sops_age_key_file != "") ||
      (var.sops_secrets_file == "" && var.sops_age_key_file == "")
    )
    error_message = "SOPS is half-configured: set BOTH sops_secrets_file and sops_age_key_file to enable it, or leave BOTH blank to disable."
  }
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
  tags      = sort([local.tag_project, each.value.os, local.node_ip[each.key], "terraform"])
  bios      = each.value.bios
  machine   = each.value.bios == "ovmf" ? "q35" : null

  # Hard-stop (not graceful shutdown) on destroy, so teardown never blocks waiting
  # on the guest agent if it isn't running (a desktop-class guest is the worst case).
  stop_on_destroy = true

  # Guest agent on: adds the virtio guest-agent channel so qemu-guest-agent runs
  # (clean shutdown + IP reporting). NOTE: tofu apply now waits for the agent to
  # report per node during create.
  agent {
    enabled = true
  }

  clone {
    vm_id = each.value.template_id
    full  = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = each.value.disk_size
  }

  dynamic "efi_disk" {
    for_each = each.value.bios == "ovmf" ? [1] : []
    content {
      datastore_id      = var.datastore_id
      file_format       = "raw"
      type              = "4m"
      pre_enrolled_keys = false
    }
  }

  # Single access port tagged into this node's VLAN.
  network_device {
    bridge  = var.lan_bridge
    model   = "virtio"
    vlan_id = each.value.vlan
  }

  initialization {
    datastore_id = var.datastore_id

    # ciupgrade=0 — skip cloud-init's first-boot apt upgrade. These nodes use a
    # custom user_data_file_id (cicustom), so this Proxmox flag doesn't drive the
    # upgrade on its own; package_upgrade in the user-data is the effective lever
    # and is also off. Ansible owns patching.
    upgrade = false

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
