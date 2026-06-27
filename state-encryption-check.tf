# Advisory reminder only — does NOT enable encryption. Encryption is opt-in via
# the TF_ENCRYPTION env var (see RUNBOOK.md section 1b). This detects whether
# TF_ENCRYPTION is set and, if not, emits a WARNING that state is plaintext.
# The check never fails the run.

data "external" "encryption_state" {
  # Inline program (no script file in the repo): reports whether TF_ENCRYPTION is set.
  program = ["bash", "-c", "cat >/dev/null; if [ -n \"$TF_ENCRYPTION\" ]; then echo '{\"enabled\":\"true\"}'; else echo '{\"enabled\":\"false\"}'; fi"]
}

check "state_encryption" {
  assert {
    condition     = data.external.encryption_state.result.enabled == "true"
    error_message = "State encryption is OFF — terraform.tfstate is plaintext and holds secrets (mesh SSH keys, Proxmox/Cloudflare tokens, ansible password). Enable it via TF_ENCRYPTION; see RUNBOOK.md section 1b. (Reminder only — not a failure.)"
  }
}
