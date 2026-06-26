# v2e-v3 Runbook

A VyOS router fronting four VLAN subnets, with three nodes behind it, deployed by
OpenTofu + cloud-init. Everything is driven by `tofu apply` — no console steps.

```
        your mac ── ssh -p 2201 v2e@<wan> ─┐ (DNAT → control:22)
                                           ▼
   vmbr0 (WAN) ── eth0 ─┐   VyOS router (created first)
   vmbr1 (trunk) ─ eth1 ┴─ vif 100/101/102/103
        VLAN 100  10.1.0.1/24  vyos-mgmt
        VLAN 101  10.1.1.1/24  control  → control  10.1.1.10  (Ubuntu)
        VLAN 102  10.1.2.1/24  services → services 10.1.2.10  (Ubuntu)
        VLAN 103  10.1.3.1/24  agent    → agent    10.1.3.10  (Debian)
```

## 0. One-time prerequisites (Proxmox node)

- Templates exist: **VyOS 9000** (cloud-init image — see `~/Documents/vyos/cloudinit-image/`), Ubuntu **9001**, Debian **9002**.
- `pvesm set local --content iso,vztmpl,backup,snippets`  (snippets enabled)
- **`vmbr1` is VLAN-aware** (Datacenter → node → Network → vmbr1 → VLAN aware → Apply).
- API token `terraform@pve!tf=…` and passwordless `ssh root@192.168.1.1`.
- WAN: the PVE host (`192.168.1.1`) NATs the lab, so `wan_gateway = "192.168.1.1"`.

## 1. Configure (`terraform.tfvars`)

```hcl
proxmox_endpoint       = "https://192.168.1.10:8006"
proxmox_api_token      = "terraform@pve!tf=<uuid>"
node_name              = "pve"
workstation_public_key = "ssh-ed25519 AAAA... user@email.me"   # cat ~/.ssh/id_ed25519.pub
wan_address            = "192.168.1.2/24"
wan_gateway            = "192.168.1.1"
cluster_password       = "ChangeMe123!"     # v2e user on the nodes
agent_password         = "ChangeMe123!"     # agent user on the nodes
# router_password_hash = "$6$..."           # OPTIONAL custom router console pw (else vyos/vyos)
```

## 2. Deploy

```bash
cd ~/Documents/v2e-v3
tofu init        # first time
tofu plan
tofu apply
```
Router boots and self-configures, waits `router_boot_wait` (120s), then the 3 nodes.

## 3. Access

VMs are recreated each apply, so clear stale host keys first:
```bash
ssh-keygen -R 192.168.1.2 ; ssh-keygen -R "[192.168.1.2]:2201"
```
```bash
ssh vyos@192.168.1.2            # router, by key (console fallback: vyos/vyos)
ssh -p 2201 v2e@192.168.1.2     # control, by key (DNAT)
# from control — the v2e mesh:
v2e@control:~$ ssh services
v2e@control:~$ ssh agent
v2e@control:~$ ssh vyos@10.1.1.1     # manage the router by key
# the agent mesh (hub = agent node):
v2e@agent:~$ sudo -iu agent
agent@agent:~$ ssh control ; ssh services
```
`tofu output` prints all of these.

## 4. Day-2

```bash
tofu apply -replace='proxmox_virtual_environment_vm.vyos'   # rebuild just the router
tofu apply -replace='proxmox_virtual_environment_vm.node["agent"]'  # rebuild one node
tofu destroy                                                # tear it all down
```

## Hard-won gotchas (don't re-learn these)

- **VyOS needs a cloud-init-*built* image.** The free nightly ISO has **no cloud-init** — `install image` templates silently ignore it. Build the qcow2 with `vyos-build` (kit in `~/Documents/vyos/cloudinit-image/`).
- **Router login (keys/password) goes in TOP-LEVEL cloud-config**, not `vyos_config_commands`. VyOS cloud-init never runs a `commit`, so `set system login … plaintext-password/public-keys` is written but never activated. Use `ssh_authorized_keys:` + a **pre-hashed** `password:` — `cc_vyos` applies those to the default `vyos` user. (Nodes are normal cloud images, so their `users:`/passwords work fine.)
- A cloud-init-built VyOS image clones with clean **`eth0`/`eth1`** (no `hw-id` pin); the ISO-install template had an `eth1`/`eth2` offset.
- **`wan_gateway` is the PVE host** (`192.168.1.1`), which NATs the lab to the internet — not a separate router.
- **macOS quirks:** `sed -i '' '…'` (BSD needs the `''`); no `openssl passwd -6` — hash with `python3 -c 'import crypt; print(crypt.crypt("pw", crypt.mksalt(crypt.METHOD_SHA512)))'`.
- **Pasting into zsh:** don't paste inline `# comments` or stacked `ssh` commands — comments get run, and an interactive `ssh` eats the next pasted line.
- Host keys change on every recreate → `ssh-keygen -R` before reconnecting.
