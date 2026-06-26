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
  private key lives only on the hub node):
  - **`v2e`** — hub **control** → `ssh services` / `ssh agent` reaches `v2e@…`.
  - **`agent`** — hub **agent node** → from `agent@agent`: `ssh control` /
    `ssh services` reaches `agent@…`. Reach it via `sudo -iu agent` on the agent node.
- **Internet:** VyOS masquerades `10.1.0.0/16` out eth0; inter-VLAN routing is
  on by default (no firewall), so control reaches the others directly.

## Prerequisites (one-time, on the Proxmox host)

1. **Templates built:** VyOS `9000`, Ubuntu `9001`, Debian `9002`.
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

ssh v2e@192.168.1.2                      # manage VyOS directly (mac is on WAN)
ssh -p 2201 v2e@192.168.1.2             # -> control node
# then, from control:
ssh services
ssh agent
```

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
