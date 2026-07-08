###############################################################################
# Proxmox vzdump backup schedule — daily whole-VM backups, LOCAL storage only.
#
# Coarse but fastest restore path (see task-backup-dr-vzdump-truenas in the
# brain): whole-VM snapshots, not file-level. The second, file-level piece
# (pg_dump + named docker volumes + acme.json -> an external/TrueNAS target)
# is a separate Ansible role, deliberately NOT duplicated here.
#
# Scope: services/agent/infra only (VMIDs node_vmid_base+2/+3/+4) — NOT
# control (which holds the mesh SSH keys + SOPS age key in plaintext on disk
# per docs-secrets-residual-exposure; a control backup needs its own,
# separately-reviewed handling) and NOT the VyOS router (its cloud-init is
# already the source of truth in this repo — see tf-router-first-ordering —
# so a vzdump snapshot of it would just be a redundant, harder-to-audit copy
# of what Terraform already reproduces from scratch).
###############################################################################

variable "backup_storage_id" {
  description = <<-EOT
    Datastore for vzdump backup archives. Deliberately NOT var.datastore_id
    (defaults to local-lvm): LVM-thin storage backs VM disks only and does
    not support the "backup" content type in Proxmox. Defaults to "local"
    (a directory-type storage), matching var.snippet_datastore_id's default
    for the same reason — both need file-based content types local-lvm can't
    provide.
  EOT
  type        = string
  default     = "local"
}

variable "backup_schedule" {
  description = "systemd calendar-event schedule for the backup job. Default: daily at 02:00."
  type        = string
  default     = "*-*-* 02:00"
}

variable "backup_keep_daily" {
  description = "Daily backups to retain."
  type        = number
  default     = 7
}

variable "backup_keep_weekly" {
  description = "Weekly backups to retain."
  type        = number
  default     = 4
}

resource "proxmox_backup_job" "v2e_daily" {
  id       = "v2e-daily"
  schedule = var.backup_schedule
  storage  = var.backup_storage_id
  node     = var.node_name
  mode     = "snapshot"
  compress = "zstd"

  # services, agent, infra only — see file header for why control + vyos are excluded.
  vmid = [for k, n in local.nodes : tostring(n.vm_id) if k != "control"]

  prune_backups = {
    keep_daily  = var.backup_keep_daily
    keep_weekly = var.backup_keep_weekly
  }
}
