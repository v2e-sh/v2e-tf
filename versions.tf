terraform {
  # 1.9.0 floor: variable validation rules reference other variables
  # (wan_gateway's rule reads var.wan_address), a feature added in OpenTofu 1.9.
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.3"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.21"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}
