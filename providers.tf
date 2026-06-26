provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  insecure  = var.proxmox_insecure
  api_token = var.proxmox_api_token != "" ? var.proxmox_api_token : null

  # SSH is required to upload cloud-init snippets (the API can't write snippets).
  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}
