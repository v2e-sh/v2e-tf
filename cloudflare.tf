###############################################################################
# Cloudflare Tunnel — outbound SSH path to the control node (key auth only).
#
#   you ── ssh lab.v2e.sh ──> Cloudflare edge
#   lab.v2e.sh  --(proxied CNAME)-->  <tunnel-id>.cfargotunnel.com
#                                │
#                cloudflared on the CONTROL node ──> ssh://localhost:22
#
# cloudflared dials OUT from control over 443/QUIC (through the VyOS masquerade),
# so there is no inbound port to open. The SSH public key is NOT sent to
# Cloudflare — the tunnel only proxies TCP; the workstation key already authorized
# on control (existing cloud-init) authenticates the session. No Cloudflare Access
# gate here on purpose: Ansible layers Zero Trust / OTP on later, out of band.
#
# OPTIONAL: gated on `local.cloudflare_enabled`. Leave cloudflare_api_token /
# cloudflare_account_id / cloudflare_zone_id blank and every resource here drops
# out (count = 0) — `terraform apply` does exactly what it does today.
###############################################################################

locals {
  # Feature switch: on only when ALL three credentials are set. nonsensitive() on
  # the token check keeps this boolean (used in count) unmarked — whether the
  # feature is on is not itself a secret.
  cloudflare_enabled = (
    nonsensitive(var.cloudflare_api_token != "") &&
    var.cloudflare_account_id != "" &&
    var.cloudflare_zone_id != ""
  )
}

# Warn (don't block) if the three creds are set inconsistently.
check "cloudflare_vars_consistent" {
  assert {
    condition = (
      (var.cloudflare_api_token != "" && var.cloudflare_account_id != "" && var.cloudflare_zone_id != "") ||
      (var.cloudflare_api_token == "" && var.cloudflare_account_id == "" && var.cloudflare_zone_id == "")
    )
    error_message = "Cloudflare config is partial: set ALL of cloudflare_api_token / cloudflare_account_id / cloudflare_zone_id to enable the tunnel, or leave ALL blank to disable it."
  }
}

provider "cloudflare" {
  # Empty when disabled — harmless, the provider is only configured if a resource
  # below actually needs it (all count = 0 when disabled).
  api_token = var.cloudflare_api_token
}

# --- The remote-managed tunnel ---------------------------------------------
# config_src = "cloudflare" => ingress lives in Cloudflare (set by *_config
# below); the connector authenticates with the run token.
resource "cloudflare_zero_trust_tunnel_cloudflared" "ssh" {
  count      = local.cloudflare_enabled ? 1 : 0
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  config_src = "cloudflare"
}

# --- Connector run token (DATA SOURCE) -------------------------------------
# .token is handed to `cloudflared service install <TOKEN>` on control (nodes.tf
# feeds it into the control node's cloud-init).
data "cloudflare_zero_trust_tunnel_cloudflared_token" "ssh" {
  count      = local.cloudflare_enabled ? 1 : 0
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.ssh[0].id
}

# --- Tunnel ingress config -------------------------------------------------
# v5: `config` is a nested attribute; the final ingress rule MUST be the
# service-only catch-all.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "ssh" {
  count      = local.cloudflare_enabled ? 1 : 0
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.ssh[0].id

  config = {
    ingress = [
      {
        hostname = var.tunnel_hostname # lab.v2e.sh
        service  = "ssh://localhost:22"
      },
      {
        service = "http_status:404" # mandatory catch-all, must be last
      },
    ]
  }
}

# --- Proxied CNAME: lab.v2e.sh -> the tunnel -------------------------------
# v5 resource is cloudflare_dns_record; target field is `content`. ttl = 1
# ("automatic") is required for proxied (orange-cloud) records.
resource "cloudflare_dns_record" "ssh" {
  count   = local.cloudflare_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.tunnel_dns_name # "lab"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.ssh[0].id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}
