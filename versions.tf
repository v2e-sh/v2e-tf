terraform {
  required_version = ">= 1.5.0"

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
