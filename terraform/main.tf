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

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node
  url          = var.image_url
  file_name    = "ubuntu-24.04-minimal-cloudimg-amd64.img"
}

resource "proxmox_virtual_environment_file" "vendor_data" {
  content_type = "snippets"
  datastore_id = var.snippets_datastore
  node_name    = var.proxmox_node

  source_raw {
    file_name = "k3s-vendor-data.yaml"
    data      = <<-EOF
      #cloud-config
      packages:
        - qemu-guest-agent
      runcmd:
        - systemctl enable --now qemu-guest-agent
    EOF
  }
}

resource "proxmox_virtual_environment_vm" "template" {
  name      = "k3s-ubuntu-2404-template"
  node_name = var.proxmox_node
  vm_id     = var.template_vmid
  template  = true
  started   = false

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  serial_device {}

  vga {
    type = "serial0"
  }

  disk {
    datastore_id = var.vm_datastore
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    size         = var.disk_size
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge = var.bridge
  }

  operating_system {
    type = "l26"
  }
}
