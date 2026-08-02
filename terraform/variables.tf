variable "proxmox_insecure" {
  description = "Skip TLS verification (Proxmox self-signed certs)"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name as shown in the Proxmox UI sidebar"
  type        = string
}

variable "image_url" {
  description = "Cloud image to build the template from"
  type        = string
  default     = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
}

variable "image_datastore" {
  description = "Datastore that stores the downloaded image (needs 'ISO image' content type)"
  type        = string
  default     = "local"
}

variable "snippets_datastore" {
  description = "Datastore with 'Snippets' content type enabled"
  type        = string
  default     = "local"
}

variable "vm_datastore" {
  description = "Datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Network bridge for VM NICs"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Default gateway for node static IPs"
  type        = string
  default     = "192.168.30.1"
}

variable "dns_servers" {
  description = "DNS servers for the nodes"
  type        = list(string)
  default     = ["192.168.30.1"]
}

variable "ssh_public_key_file" {
  description = "Path to the SSH public key installed for vm_user"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "vm_user" {
  description = "Cloud-init user created on each node"
  type        = string
  default     = "ansibleuser"
}

variable "template_vmid" {
  description = "VM ID for the cloud-image template"
  type        = number
  default     = 920
}

variable "disk_size" {
  description = "Template disk size in GB (inherited by clones)"
  type        = number
  default     = 32
}

variable "nodes" {
  description = "k3s node VMs: name => vmid, ip (CIDR), cores, memory (MiB)"
  type = map(object({
    vmid   = number
    ip     = string
    cores  = number
    memory = number
  }))
}
