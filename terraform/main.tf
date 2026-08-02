terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.73"
    }
  }
}

# Authentication comes from environment variables:
#   PROXMOX_VE_ENDPOINT  e.g. https://192.168.30.43:8006/
#   PROXMOX_VE_API_TOKEN e.g. terraform@pve!provision=<uuid>
# The ssh block is used to upload cloud-init snippets to the Proxmox host;
# it authenticates via your local ssh-agent as root.
provider "proxmox" {
  insecure = var.proxmox_insecure

  ssh {
    agent    = true
    username = "root"
  }
}
