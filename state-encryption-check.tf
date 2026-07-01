###############################################################################
# State-encryption reminder (TF-3 / Q4)
#
# OpenTofu can't read arbitrary env vars from HCL, so HCL alone can't tell whether
# state encryption is on. This tiny `external` program runs at plan/apply time with
# tofu's own environment and reports whether TF_ENCRYPTION is set; the check below
# then emits a non-blocking WARNING when it isn't. It never fails an apply — it only
# reminds you that state + plan files hold secrets (both mesh SSH private keys, the
# Proxmox + Cloudflare tokens, and the SOPS age key) in PLAINTEXT.
#
# Turn encryption on per RUNBOOK Step 3 (export TF_ENCRYPTION), or ignore this for a
# throwaway lab.
###############################################################################

data "external" "state_encryption" {
  program = ["sh", "-c", "if [ -n \"$TF_ENCRYPTION\" ]; then printf '{\"enabled\":\"true\"}'; else printf '{\"enabled\":\"false\"}'; fi"]
}

check "state_encryption_active" {
  assert {
    condition = data.external.state_encryption.result.enabled == "true"
    error_message = join(" ", [
      "OpenTofu state encryption is OFF (TF_ENCRYPTION is unset).",
      "State and plan files store secrets in PLAINTEXT — the mesh SSH private keys,",
      "the Proxmox + Cloudflare tokens, and the SOPS age key.",
      "Enable it per RUNBOOK Step 3 (export TF_ENCRYPTION), or accept plaintext state for a throwaway lab.",
    ])
  }
}
