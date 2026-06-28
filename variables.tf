###############################################################################
# Proxmox connection
###############################################################################

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint, e.g. https://192.168.1.10:8006"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token 'USER@REALM!TOKENID=UUID'. Leave empty to use PROXMOX_VE_API_TOKEN env var."
  type        = string
  default     = ""
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (self-signed certs)."
  type        = bool
  default     = true
}

variable "proxmox_ssh_username" {
  description = "SSH user on the Proxmox node (needed to upload cloud-init snippets)."
  type        = string
  default     = "root"
}

variable "node_name" {
  description = "Proxmox node to deploy on."
  type        = string
}

variable "datastore_id" {
  description = "Datastore for VM disks (e.g. local-lvm)."
  type        = string
  default     = "local-lvm"
}

variable "snippet_datastore_id" {
  description = "Datastore with the 'snippets' content type enabled (e.g. local)."
  type        = string
  default     = "local"
}

###############################################################################
# Bridges / addressing
###############################################################################

variable "wan_bridge" {
  description = "Proxmox bridge providing internet (VyOS WAN / eth0)."
  type        = string
  default     = "vmbr0"
}

variable "lan_bridge" {
  description = "VLAN-aware Proxmox bridge carrying all LAN subnets (VyOS LAN trunk / eth1, and node access ports)."
  type        = string
  default     = "vmbr1"
}

variable "network_prefix" {
  description = "First two octets of the lab network. Subnets are <prefix>.<n>.0/24."
  type        = string
  default     = "10.1"
}

variable "subnet_mask" {
  description = "Prefix length for each /24 subnet."
  type        = number
  default     = 24
}

variable "lan_supernet" {
  description = "Supernet used for the source-NAT (masquerade) rule covering all LAN subnets."
  type        = string
  default     = "10.1.0.0/16"
}

variable "name_servers" {
  description = "Upstream DNS resolvers for the router and the nodes."
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}

###############################################################################
# Templates to clone
###############################################################################

variable "vyos_template_id" {
  description = "VMID of the VyOS template."
  type        = number
  default     = 9000
}

variable "ubuntu_template_id" {
  description = "VMID of the Ubuntu template (control + services)."
  type        = number
  default     = 9001
}

variable "debian_template_id" {
  description = "VMID of the Debian template (agent)."
  type        = number
  default     = 9002
}

###############################################################################
# VyOS router
###############################################################################

variable "vyos_name" {
  description = "Name/hostname of the VyOS router VM."
  type        = string
  default     = "v2e-vyos"
}

variable "vyos_vmid" {
  description = "VMID for the VyOS router."
  type        = number
  default     = 310
}

variable "vyos_cores" {
  type    = number
  default = 1
}

variable "vyos_memory" {
  type    = number
  default = 1024
}

variable "vyos_disk_size" {
  description = "Must match the VyOS template disk (10G)."
  type        = number
  default     = 10
}

variable "vyos_wan_interface" {
  description = "Guest interface name for the WAN NIC (net0). The cloud-init-built VyOS image bakes no hw-id, so clones get clean naming: eth0."
  type        = string
  default     = "eth0"
}

variable "vyos_lan_interface" {
  description = "Guest interface name for the LAN trunk NIC (net1). eth1 on the cloud-init image."
  type        = string
  default     = "eth1"
}

variable "router_password_hash" {
  description = "PRE-HASHED (sha-512 crypt) console password for the VyOS bootstrap 'vyos' user, e.g. `openssl passwd -6 'yourpass'`. Empty = key-only (console fallback is the image default vyos/vyos). Plaintext does NOT work: cc_vyos honors only an already-hashed value. Phase-2 Ansible takes over router login config from here."
  type        = string
  default     = ""
  sensitive   = true
}

variable "wan_address" {
  description = "VyOS WAN (eth0) address. 'dhcp' or a CIDR like '192.168.1.2/24'. A static IP is recommended so the SSH port-forward target is predictable."
  type        = string
  default     = "dhcp"
}

variable "wan_gateway" {
  description = "Default gateway for a static WAN. Ignored when wan_address = 'dhcp'."
  type        = string
  default     = ""
}

variable "router_boot_wait" {
  description = "How long to wait after the router VM is created before building the nodes (lets VyOS boot + apply routing). Go duration string."
  type        = string
  default     = "120s"
}

variable "extra_vyos_commands" {
  description = "Extra raw 'set ...' VyOS commands appended to cloud-init."
  type        = list(string)
  default     = []
}

variable "firewall_enabled" {
  description = "Apply the VyOS default-deny firewall (WAN/inter-VLAN/agent isolation) when the router is built."
  type        = bool
  default     = true
}

variable "trusted_mgmt_sources" {
  description = "CIDRs allowed to SSH the router itself over the WAN, e.g. [\"203.0.113.5/32\"]. Empty = no WAN SSH to the router (manage it via control). Does not affect the control DNAT."
  type        = list(string)
  default     = []
}

###############################################################################
# Nodes (control / services / agent)
###############################################################################

variable "node_vmid_base" {
  description = "Base VMID; control=base+1, services=base+2, agent=base+3."
  type        = number
  default     = 310
}

variable "node_host_octet" {
  description = "Last octet for each node's static IP (e.g. 10 => 10.1.1.10, 10.1.2.10, 10.1.3.10)."
  type        = number
  default     = 10
}

variable "node_cores" {
  type    = number
  default = 2
}

variable "node_memory" {
  type    = number
  default = 2048
}

variable "node_disk_size" {
  description = "Must be >= the cloud-image template disk (20G)."
  type        = number
  default     = 20
}

variable "cluster_user" {
  description = "Uniform login user created on all 3 nodes. Control holds the cluster private key; members authorize the public key."
  type        = string
  default     = "v2e"
}

variable "sudo_password" {
  description = "Required sudo password for the primary (v2e) user. SSH is key-only; sudo uses this password."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.sudo_password)) > 0 && !contains(["v2e", "ansible", "password", "changeme", "changeme123!"], lower(trimspace(var.sudo_password)))
    error_message = "sudo_password is required and must not be a known-weak value (v2e/ansible/password/changeme)."
  }
}

variable "ansible_user" {
  description = "Dedicated automation account present on all nodes. Hub = control; reaches every node + the VyOS router with NOPASSWD sudo. No password (locked); used only by Ansible and via 'sudo su'. Phase-2 Ansible authenticates and runs as this user."
  type        = string
  default     = "ansible"
}

variable "ansible_vault_password" {
  description = "Ansible Vault password, written to /home/<ansible_user>/.vault_pass on control (the bootstrap runner) so vaulted vars decrypt. Blank = not seeded (no file written; Ansible runs without vault). WARNING: kept in tfvars + tf state in plaintext."
  type        = string
  default     = ""
  sensitive   = true
}

variable "package_upgrade" {
  description = "Run apt upgrade on first boot of the nodes."
  type        = bool
  default     = true
}

variable "extra_packages" {
  description = "Extra apt packages installed on all nodes."
  type        = list(string)
  default     = []
}

###############################################################################
# Access
###############################################################################

variable "workstation_public_key" {
  description = "Your mac's SSH public key (cat ~/.ssh/id_ed25519.pub). Authorized on the control node and VyOS."
  type        = string

  validation {
    condition     = trimspace(var.workstation_public_key) != ""
    error_message = "Set workstation_public_key to your mac's public key, e.g. run: cat ~/.ssh/id_ed25519.pub"
  }
}

variable "authorize_workstation_on_all_nodes" {
  description = "Also authorize your mac key on services + agent (not just control). Default false: reach them via control."
  type        = bool
  default     = false
}

variable "control_ssh_wan_port" {
  description = "Port on the VyOS WAN that is DNAT-forwarded to the control node's SSH (22)."
  type        = number
  default     = 2201
}

###############################################################################
# Cloudflare tunnel (optional SSH path to control; see cloudflare.tf)
# Leave the three creds BLANK to disable the whole feature — apply is unchanged.
###############################################################################

variable "cloudflare_api_token" {
  description = "Cloudflare API token. Scopes: Account > Cloudflare Tunnel:Edit, Zone > DNS:Edit, Zone > Zone:Read. Blank = tunnel disabled."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (dash: Manage Account > Account ID). Blank = tunnel disabled."
  type        = string
  default     = ""
}

variable "cloudflare_zone_id" {
  description = "Zone ID for the domain hosting tunnel_hostname, e.g. v2e.sh (dash: zone Overview > API). Blank = tunnel disabled."
  type        = string
  default     = ""
}

variable "tunnel_name" {
  description = "Name of the Cloudflare tunnel (shown in the Zero Trust dashboard)."
  type        = string
  default     = "v2e-control-ssh"
}

variable "tunnel_hostname" {
  description = "Public hostname routed through the tunnel to control's sshd."
  type        = string
  default     = "lab.v2e.sh"
}

variable "tunnel_dns_name" {
  description = "DNS record label for the proxied CNAME (the subdomain part of tunnel_hostname)."
  type        = string
  default     = "lab"
}

###############################################################################
# Ansible bootstrap (control node only)
# On by default: the control node (mesh hub) clones the repo on first boot and
# runs the playbook against the whole mesh over its existing v2e SSH trust.
# Set ansible_repo_url = "" to disable — apply is then unchanged.
###############################################################################

variable "ansible_repo_url" {
  description = "Public git URL of the Ansible repo cloned + run on control at first boot. Blank = bootstrap disabled."
  type        = string
  default     = "https://github.com/v2e-sh/v2e-ansible"
}

variable "ansible_repo_ref" {
  description = "Branch, tag, or commit to clone from ansible_repo_url. Pinned to a commit for a reproducible first boot; bump it when you cut a new Ansible release."
  type        = string
  default     = "608af5ff8e0dbc4c0fc871f50663bab08dbb255a"
}

variable "ansible_version" {
  description = "Pin the pipx-installed Ansible on control, e.g. \"11.1.0\". Empty = latest at first boot (not reproducible)."
  type        = string
  default     = ""
}

variable "ansible_playbook" {
  description = "Playbook to run, relative to the repo root."
  type        = string
  default     = "site.yml"
}

variable "ansible_inventory" {
  description = "Inventory file to use, relative to the repo root. Hosts must be reachable from control as the ansible automation user (control = local, services via direct SSH as ansible)."
  type        = string
  default     = "inventory/hosts.ini"
}
