provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  insecure  = var.proxmox_insecure
  api_token = var.proxmox_api_token != "" ? var.proxmox_api_token : null

  # SSH is required to upload cloud-init snippets (the API can't write snippets).
  ssh {
    agent    = true
    username = var.proxmox_ssh_username

    # Pin snippet-upload SSH to the API endpoint host (the reachable mgmt IP)
    # instead of the node's API-reported primary IP, which sits on a flaky WAN
    # path and intermittently breaks `tofu apply` mid-flight.
    node {
      name    = var.node_name
      address = regex("^https?://([^:/]+)", var.proxmox_endpoint)[0]
    }
  }
}
