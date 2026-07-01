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
#
# image -> Packer template -> Proxmox VMID chain (built by v2e-packer):
#   Ubuntu 24.04 cloud image -> ubuntu-2404-pk -> 9001 (prod) / 9901 (staging)
#   Debian 13   cloud image -> debian-13-pk   -> 9002 (prod) / 9902 (staging)
# VyOS is still the hand-built cloud-init image at 9000 (not yet Packer-built).
# Defaults point at the PRODUCTION VMIDs (Packer is being promoted to these).
# While a template still lives at its staging VMID, override in tfvars:
#   ubuntu_template_id = 9901 ; debian_template_id = 9902
###############################################################################

variable "vyos_template_id" {
  description = "VMID of the VyOS template (hand-built cloud-init image; not yet Packer-built)."
  type        = number
  default     = 9000
}

variable "ubuntu_template_id" {
  description = "VMID of the Ubuntu template for control + services. Packer 'ubuntu-2404-pk' from the Ubuntu 24.04 cloud image. Prod 9001 / staging 9901."
  type        = number
  default     = 9001
}

variable "debian_template_id" {
  description = "VMID of the Debian template for agent. Packer 'debian-13-pk' from the Debian 13 cloud image. Prod 9002 / staging 9902."
  type        = number
  default     = 9002
}

variable "parrot_template_id" {
  description = "VMID of the ParrotOS Home template (control workstation)."
  type        = number
  default     = 9003
}

###############################################################################
# VyOS router
###############################################################################

variable "vyos_name" {
  description = "Name/hostname of the VyOS router VM."
  type        = string
  default     = "router"
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

variable "agent_egress_restricted" {
  description = "Deny-by-default internet egress for the agent (AI) node (Q1, zero-trust for the AI VLAN). true: the agent reaches the internet only via the allowlist — DNS to name_servers, NTP, and agent_egress_allow_tcp_ports. false: open egress like the other nodes. control + services always keep open egress. Requires firewall_enabled."
  type        = bool
  default     = true
}

variable "agent_egress_allow_tcp_ports" {
  description = "TCP destination ports the agent node may reach on the internet when agent_egress_restricted = true (DNS/53 and NTP/123 are always allowed). Default 80/443 covers apt, git, container pulls, and HTTPS APIs; add ports the agent legitimately needs."
  type        = list(number)
  default     = [80, 443]
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

variable "control_cores" {
  description = "vCPU cores for the control node (ParrotOS workstation)."
  type        = number
  default     = 4
}

variable "control_memory" {
  description = "Memory (MB) for the control node (ParrotOS workstation)."
  type        = number
  default     = 8192
}

variable "control_disk_size" {
  description = "Disk size (GB) for the control node. Must be >= the ParrotOS template disk."
  type        = number
  default     = 64
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
  description = "Run apt upgrade on first boot of the nodes. Default false: Ansible owns patching and the first-boot upgrade is slow. Set true to patch before the Ansible bootstrap runs."
  type        = bool
  default     = false
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

variable "cloudflare_access_emails" {
  description = "Emails allowed through a Cloudflare Access (one-time PIN) gate in front of tunnel_hostname. Empty = no Access gate (tunnel is key-only SSH). Requires the Cloudflare tunnel vars to be set."
  type        = list(string)
  default     = []
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
  description = "Git branch or tag of ansible_repo_url to check out on control at first boot (git clone --branch). Empty = the repo's default branch (main). Use to deploy a feature branch whose app-stack code isn't on main yet."
  type        = string
  default     = ""
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

###############################################################################
# Secrets — SOPS + age (optional; blank = feature off)
#
# One locally-encrypted SOPS file, decrypted on control at first boot with an age
# private key. Both are written by control's cloud-init (see node.yaml.tftpl):
#   sops_secrets_file -> /home/<ansible_user>/ansible/group_vars/all.sops.yaml (0600)
#     (the `.sops.yaml` extension is required for community.sops auto-decryption)
#   sops_age_key_file -> /home/<ansible_user>/.config/sops/age/keys.txt  (0600)
# Workflow (local machine):
#   age-keygen -o keys.txt
#   sops --encrypt --age <PUBLIC-key-from-keys.txt> secrets.yaml > secrets.sops.yaml
#   then set the two vars below to those file paths.
# NOTE: the age PRIVATE key is read into tf state + the cloud-init snippet (as the
# mesh keys already are) — treat state as sensitive and rotate on a clean rebuild.
# Intended to supersede ansible_vault_password (D-1); both can coexist for now.
###############################################################################

variable "sops_secrets_file" {
  description = "Path to a locally sops-encrypted secrets file; placed on control as ansible/group_vars/all.sops.yaml for Ansible + Compose to consume. Blank = not placed."
  type        = string
  default     = ""
}

variable "sops_age_key_file" {
  description = "Path to the age PRIVATE key that decrypts sops_secrets_file; written to control's ~/.config/sops/age/keys.txt so sops auto-discovers it. Blank = not written."
  type        = string
  default     = ""
}
