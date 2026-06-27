###############################################################################
# Topology model — derived from variables. One place to see the whole lab.
#
#   WAN (vmbr0) ── eth0 ──┐
#                         │  VyOS router (created FIRST)
#   LAN (vmbr1 trunk) ─ eth1 ─ vif 100/101/102/103
#                         │
#   VLAN 100  10.1.0.1/24  vyos-mgmt   (router only)
#   VLAN 101  10.1.1.1/24  control  -> control  node 10.1.1.10
#   VLAN 102  10.1.2.1/24  services -> services node 10.1.2.10
#   VLAN 103  10.1.3.1/24  agent    -> agent    node 10.1.3.10
###############################################################################

locals {
  # subnet key => { octet (3rd octet / id), vlan tag, descriptive name }
  subnets = {
    mgmt     = { octet = 0, vlan = 100, name = "vyos-mgmt" }
    control  = { octet = 1, vlan = 101, name = "control" }
    services = { octet = 2, vlan = 102, name = "services" }
    agent    = { octet = 3, vlan = 103, name = "agent" }
  }

  # VyOS eth1 VLAN sub-interfaces (the router's gateway IP in each subnet).
  vlans = [for name, s in local.subnets : {
    id           = s.vlan
    name         = s.name
    gateway_cidr = "${var.network_prefix}.${s.octet}.1/${var.subnet_mask}"
  }]

  # Semicolon-separated VLAN list for the bpg trunk port (ranges are unsupported).
  trunk_string = join(";", [for v in local.vlans : tostring(v.id)])

  # The three VMs behind the router.
  nodes = {
    control = {
      vm_id       = var.node_vmid_base + 1
      template_id = var.ubuntu_template_id
      octet       = 1
      vlan        = 101
      role        = "control"
    }
    services = {
      vm_id       = var.node_vmid_base + 2
      template_id = var.ubuntu_template_id
      octet       = 2
      vlan        = 102
      role        = "member"
    }
    agent = {
      vm_id       = var.node_vmid_base + 3
      template_id = var.debian_template_id
      octet       = 3
      vlan        = 103
      role        = "member"
    }
  }

  node_ip      = { for k, n in local.nodes : k => "${var.network_prefix}.${n.octet}.${var.node_host_octet}" }
  node_ip_cidr = { for k, n in local.nodes : k => "${local.node_ip[k]}/${var.subnet_mask}" }
  node_gateway = { for k, n in local.nodes : k => "${var.network_prefix}.${n.octet}.1" }
  control_ip   = local.node_ip["control"]

  # SSH trust meshes. Each mesh = a login user that exists on EVERY node, with a
  # single keypair: the hub node holds the private key and can ssh to the rest;
  # every node authorizes the public key for that user.
  #
  # - primary (v2e): the human admin login. Hub = control; mac key authorized here.
  # - ansible: the dedicated automation account. Hub = control; reaches every node
  #   AND the VyOS router, with NOPASSWD sudo (granted to all mesh users below).
  #   Phase-2 Ansible runs from here; it provisions any further app users (e.g. the
  #   old 'agent' account) itself, so they are no longer created by Terraform.
  meshes = {
    primary = {
      user              = var.cluster_user # v2e
      hub               = "control"
      password          = var.cluster_password
      public            = trimspace(tls_private_key.primary.public_key_openssh)
      private           = tls_private_key.primary.private_key_openssh
      allow_workstation = true # your mac key is authorized for this user on the hub
      reaches_vyos      = true # v2e key is also authorized on the router (router.tf)
    }
    ansible = {
      user              = var.ansible_user # ansible — automation account
      hub               = "control"
      password          = var.ansible_password
      public            = trimspace(tls_private_key.ansible.public_key_openssh)
      private           = tls_private_key.ansible.private_key_openssh
      allow_workstation = false
      reaches_vyos      = true # ansible key authorized on the router (router.tf)
    }
  }

  # The router comes up with only the default VyOS login user ('vyos'), authorized
  # for both mesh keys (see admin_keys in router.tf). Both meshes therefore reach
  # it as `vyos@<control-subnet-gateway>` (e.g. vyos@10.1.1.1) — the bootstrap
  # path Ansible uses before it provisions dedicated router users of its own.
  vyos_host             = local.node_gateway["control"]
  router_bootstrap_user = "vyos"

  # Per-node user list rendered into cloud-init.
  node_users = { for k, n in local.nodes : k => [
    for mk, m in local.meshes : {
      name     = m.user
      password = m.password
      authorized_keys = compact(concat(
        [m.public],
        (m.allow_workstation && (k == m.hub || var.authorize_workstation_on_all_nodes)) ? [trimspace(var.workstation_public_key)] : [],
      ))
      is_hub      = m.hub == k
      private_key = m.hub == k ? m.private : ""
      ssh_targets = m.hub == k ? concat(
        [for tk, tn in local.nodes : { alias = tk, host = local.node_ip[tk], user = m.user } if tk != k],
        m.reaches_vyos ? [{ alias = "vyos", host = local.vyos_host, user = local.router_bootstrap_user }] : [],
      ) : []
    }
  ] }

  node_has_hub = { for k, users in local.node_users : k => anytrue([for u in users : u.is_hub]) }
}
