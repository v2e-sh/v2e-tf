# v2e-v3 — segmented lab on Proxmox (VyOS router + 3 nodes)

A VyOS router fronts four VLAN subnets on one LAN bridge (router-on-a-stick),
with three nodes behind it. Built with Terraform + cloud-init.

## Topology

```
          your mac
             │  ssh -p 2201 v2e@<vyos-wan>        (DNAT -> control:22)
             ▼
   vmbr0 (WAN) ── eth0 ─┐
                        │   VyOS router  (created FIRST)
   vmbr1 (trunk) ─ eth1 ┴─ vif 100/101/102/103
                        │
   VLAN 100  10.1.0.1/24  vyos-mgmt   (router only)
   VLAN 101  10.1.1.1/24  control  ── control  10.1.1.10  (Ubuntu)
   VLAN 102  10.1.2.1/24  services ── services 10.1.2.10  (Ubuntu)
   VLAN 103  10.1.3.1/24  agent    ── agent    10.1.3.10  (Debian)
```

- **Router first.** The 3 nodes `depends_on` a `time_sleep` that starts when the
  router VM is created, so VyOS is booting/routing before they run cloud-init.
- **Access:** your mac key is authorized on **`v2e@control`**; VyOS DNATs
  `WAN:2201 -> control:22`, so `ssh -p 2201 v2e@<vyos-wan>`.
- **Two trust meshes** (each = a user on every node + one ed25519 keypair whose
  private key lives only on the hub node — **control** for both):
  - **`v2e`** — the human admin login. From control: `ssh services` / `ssh agent`
    reaches `v2e@…`, and `ssh vyos` reaches the router.
  - **`ansible`** — the dedicated automation account (NOPASSWD sudo). From control
    it reaches every node *and* the router; phase-2 Ansible runs as this user and
    provisions any further system config — app users (e.g. the old `agent`
    account) and the router's own login users — so those are not created by Terraform.
- **Router login.** Terraform makes the router *Ansible-reachable* only: it comes up
  with the VyOS default **`vyos`** user, authorized for your mac key + both mesh
  keys, so control reaches it as `vyos@10.1.1.1` by key. Provisioning dedicated
  router users is left to phase-2 Ansible.
- **Internet:** VyOS masquerades `10.1.0.0/16` out eth0. A default-deny firewall
  (`firewall_enabled`, on by default) restricts inter-VLAN traffic to control ->
  services and control -> agent, plus LAN -> internet egress; the nodes can't
  reach each other directly.

## Prerequisites (one-time, on the Proxmox host)

1. **Templates built** (v2e-packer): VyOS `9000` (hand-built cloud-init image);
   Ubuntu `ubuntu-2404-pk` → `9001` prod / `9901` staging; Debian `debian-13-pk`
   → `9002` / `9902`. While a template is still at its staging VMID, set
   `ubuntu_template_id` / `debian_template_id` to `9901` / `9902` in tfvars.
2. **Snippets enabled** on `local`:
   ```bash
   pvesm set local --content iso,vztmpl,backup,snippets
   ```
3. **`vmbr1` exists and is VLAN-aware** — this is required for the trunk to carry
   tagged VLANs. In the UI: *Datacenter → node → Network → vmbr1 → Edit → tick
   "VLAN aware" → Apply*. Or in `/etc/network/interfaces`:
   ```
   auto vmbr1
   iface vmbr1 inet manual
       bridge-ports none
       bridge-stp off
       bridge-fd 0
       bridge-vlan-aware yes
       bridge-vids 2-4094
   ```
   then `ifreload -a`. (`vmbr1` needs no IP and no physical port for an
   isolated lab; add a port if these subnets must reach the physical LAN.)
4. **API token + passwordless SSH** to the node (snippet upload uses SSH).

## Deploy

```bash
cd ~/Documents/v2e-v3
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars        # endpoint, token, workstation_public_key, WAN

terraform init
terraform plan                  # 1 keypair + router (+snippet) + 3 nodes (+snippets) + time_sleep
terraform apply
```

`apply` creates the router, waits `router_boot_wait` (120s), then the 3 nodes.

## Access after apply

```bash
terraform output                       # all the ssh hints

ssh -p 2201 v2e@<vyos-wan>             # -> control node (DNAT WAN:2201 -> control:22)
# then, from control, reach the router + the other nodes over the mesh:
ssh vyos                               # -> VyOS router (bootstrap 'vyos' user)
ssh services
ssh agent
```

The router has **no WAN SSH by default** (firewall on, `trusted_mgmt_sources` empty)
— manage it from control as above. To allow direct `ssh vyos@<vyos-wan>`, add your
IP to `trusted_mgmt_sources`.

## Notes / gotchas

- **Static WAN recommended.** With `wan_address = "dhcp"` the port-forward still
  works, but you must discover the WAN IP (Proxmox/DHCP lease) yourself.
- **cloud-init runs once.** Changing tfvars later won't re-apply on a live VM —
  `terraform taint` / recreate the affected VM.
- **`router_boot_wait`** is a fixed delay, not a health check. Bump it on a slow
  host if nodes come up before VyOS is routing (their apt step would fail; SSH
  access still works since users/keys are set before packages).
- **agent disabled** on every VM so Terraform never blocks on a guest agent;
  IPs are static and known. qemu-guest-agent is still installed in the guests.
- **VLAN/subnet map** lives in `network.tf` (`locals.subnets`) — change it there.
- The cluster **private key is embedded** in the control node's cloud-init drive
  (unavoidable for this pattern); treat that VM's disk/snapshots accordingly.
```
# v2e-tf
