# Proxmox VM Provisioning with OpenTofu — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Declaratively provision 5 Proxmox VMs (3 control plane, 2 workers) for a new k3s cluster via OpenTofu, plus the Ansible inventory and wrapper script to go from bare Proxmox to running k3s with `./provision.sh && ansible-playbook site.yml -i inventory/minimal-cluster/hosts.ini`.

**Architecture:** A `terraform/` directory using the `bpg/proxmox` provider builds a cloud-image template (VM 920) and full-clones 5 node VMs (921–925) with cloud-init handling static IPs, the `ansibleuser` SSH key, and qemu-guest-agent install. Ansible (unchanged) configures k3s using a new gitignored `inventory/minimal-cluster/`.

**Tech Stack:** OpenTofu (installed at `/opt/homebrew/bin/tofu`), bpg/proxmox provider, Proxmox VE API token auth, cloud-init, bash, existing Ansible playbooks.

**Spec:** `docs/superpowers/specs/2026-08-02-proxmox-vm-provisioning-design.md`

## Global Constraints

- Existing cluster untouched: do not modify existing VMs, template 900, `inventory/codingworks-cluster/`, `deploy.sh`, `site.yml`, or any role.
- New node IPs: cp1–cp3 = 192.168.30.121–123 (VM IDs 921–923, 2 cores / 4096 MiB), wk1–wk2 = 192.168.30.124–125 (VM IDs 924–925, 4 cores / 8192 MiB). Template VM ID 920.
- New cluster networking: `apiserver_endpoint: 192.168.30.223`, `metal_lb_ip_range: 192.168.30.31-192.168.30.60`, gateway 192.168.30.1.
- No secrets in committed files. Proxmox credentials only via `PROXMOX_VE_ENDPOINT` / `PROXMOX_VE_API_TOKEN` env vars. `inventory/minimal-cluster/` is automatically gitignored by `inventory/.gitignore` — never `git add -f` it.
- Ubuntu 24.04 minimal cloud image: `https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img`, disk resized to 32 GB.
- SSH user on VMs: `ansibleuser`, public key from `~/.ssh/id_ed25519.pub`.
- Commit messages end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Terraform scaffolding (provider, variables, tfvars, outputs)

**Files:**
- Create: `terraform/.gitignore`
- Create: `terraform/main.tf` (provider block only in this task)
- Create: `terraform/variables.tf`
- Create: `terraform/terraform.tfvars`
- Create: `terraform/outputs.tf`

**Interfaces:**
- Produces: variables `proxmox_node`, `image_url`, `image_datastore`, `snippets_datastore`, `vm_datastore`, `bridge`, `gateway`, `dns_servers`, `ssh_public_key_file`, `vm_user`, `template_vmid`, `disk_size`, `nodes` (map of `{vmid, ip, cores, memory}`) — consumed by Tasks 2–3. Output `node_ips` (map name→bare IP) — consumed by Task 4's `provision.sh`.

- [ ] **Step 1: Create `terraform/.gitignore`**

```gitignore
.terraform/
.terraform.lock.hcl
*.tfstate
*.tfstate.*
*.auto.tfvars
crash.log
```

Note: we gitignore the lock file too; single-operator homelab, and the provider version is pinned in `main.tf`.

- [ ] **Step 2: Create `terraform/main.tf` with the provider block**

```hcl
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
```

- [ ] **Step 3: Create `terraform/variables.tf`**

```hcl
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
```

- [ ] **Step 4: Create `terraform/terraform.tfvars`**

```hcl
proxmox_node = "pve" # CHANGE to your Proxmox node name (UI sidebar)

nodes = {
  cp1 = { vmid = 921, ip = "192.168.30.121/24", cores = 2, memory = 4096 }
  cp2 = { vmid = 922, ip = "192.168.30.122/24", cores = 2, memory = 4096 }
  cp3 = { vmid = 923, ip = "192.168.30.123/24", cores = 2, memory = 4096 }
  wk1 = { vmid = 924, ip = "192.168.30.124/24", cores = 4, memory = 8192 }
  wk2 = { vmid = 925, ip = "192.168.30.125/24", cores = 4, memory = 8192 }
}
```

- [ ] **Step 5: Create `terraform/outputs.tf`**

```hcl
output "node_ips" {
  description = "Node name => IP address"
  value       = { for name, node in var.nodes : name => split("/", node.ip)[0] }
}
```

- [ ] **Step 6: Verify — init, fmt, validate**

Run:
```bash
cd terraform && tofu init && tofu fmt -check && tofu validate
```
Expected: `Terraform has been successfully initialized!` (provider bpg/proxmox downloaded), fmt exits silently, `Success! The configuration is valid.`

- [ ] **Step 7: Commit**

```bash
git add terraform/
git commit -m "feat: add OpenTofu scaffolding for Proxmox VM provisioning

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Verify `terraform/.terraform/` was NOT committed (`git status` clean of it).

---

### Task 2: Cloud image, vendor-data snippet, and template VM

**Files:**
- Modify: `terraform/main.tf` (append resources)

**Interfaces:**
- Consumes: variables from Task 1.
- Produces: `proxmox_virtual_environment_vm.template` (VM 920) and `proxmox_virtual_environment_file.vendor_data` — consumed by Task 3's clones.

- [ ] **Step 1: Append the image download resource to `terraform/main.tf`**

```hcl
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node
  url          = var.image_url
  file_name    = "ubuntu-24.04-minimal-cloudimg-amd64.img"
}
```

- [ ] **Step 2: Append the vendor-data snippet resource**

This replaces the manual "apt-get install qemu-guest-agent" post-clone step. Uploaded to the Proxmox host over SSH (hence the provider `ssh` block).

```hcl
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
```

- [ ] **Step 3: Append the template VM resource**

Mirrors the manual VM-900 recipe in `docs/node.md`: serial console + serial VGA, discard + SSD emulation, agent flag, 32G disk from the cloud image.

```hcl
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
```

- [ ] **Step 4: Verify — fmt, validate**

Run:
```bash
cd terraform && tofu fmt && tofu validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add terraform/main.tf
git commit -m "feat: add cloud image download, vendor-data snippet, and template VM

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Node VM clones

**Files:**
- Modify: `terraform/main.tf` (append resource)

**Interfaces:**
- Consumes: `proxmox_virtual_environment_vm.template`, `proxmox_virtual_environment_file.vendor_data` (Task 2), `var.nodes` (Task 1).
- Produces: 5 running VMs named `k3s-cp1`…`k3s-wk2` reachable at their static IPs — consumed by Task 4 (SSH wait) and Task 5 (Ansible inventory).

- [ ] **Step 1: Append the clone resource to `terraform/main.tf`**

Cloud-init sets the static IP (no DHCP — `static-ip.sh` not needed for VMs), creates `ansibleuser` with the operator's SSH key (Proxmox grants it passwordless sudo), and attaches the vendor-data snippet. `agent { enabled = true }` makes tofu wait until qemu-guest-agent is up — i.e., until first-boot cloud-init has installed it — so a completed apply means the VMs are genuinely ready. `stop_on_destroy` guards against destroys hanging if the agent is broken.

```hcl
resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.nodes

  name      = "k3s-${each.key}"
  node_name = var.proxmox_node
  vm_id     = each.value.vmid
  tags      = ["k3s", "minimal-cluster"]

  clone {
    vm_id = proxmox_virtual_environment_vm.template.vm_id
    full  = true
  }

  agent {
    enabled = true
  }

  stop_on_destroy = true

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  initialization {
    datastore_id = var.vm_datastore

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.vm_user
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_file)))]
    }

    vendor_data_file_id = proxmox_virtual_environment_file.vendor_data.id
  }

  network_device {
    bridge = var.bridge
  }

  operating_system {
    type = "l26"
  }
}
```

- [ ] **Step 2: Verify — fmt, validate**

Run:
```bash
cd terraform && tofu fmt && tofu validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add terraform/main.tf
git commit -m "feat: add k3s node VM clones with cloud-init static IPs

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: provision.sh wrapper

**Files:**
- Create: `provision.sh` (repo root, mode 755)

**Interfaces:**
- Consumes: `terraform/` config (Tasks 1–3), tofu output `node_ips`.
- Produces: repo-root entry point `./provision.sh` — referenced by Task 6 docs and Task 7 acceptance.

- [ ] **Step 1: Create `provision.sh`**

```bash
#!/bin/bash -e

cd "$(dirname "$0")"

if [ -z "${PROXMOX_VE_ENDPOINT:-}" ] || [ -z "${PROXMOX_VE_API_TOKEN:-}" ]; then
    echo "Error: PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN must be set."
    echo ""
    echo "Example:"
    echo "  export PROXMOX_VE_ENDPOINT=https://192.168.30.43:8006/"
    echo "  export PROXMOX_VE_API_TOKEN='terraform@pve!provision=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'"
    echo ""
    echo "See terraform/README.md for one-time API token setup."
    exit 1
fi

tofu -chdir=terraform apply

# Wait for SSH on every node. tofu apply already waits for qemu-guest-agent,
# so this is usually instant; it matters when VMs already existed but were
# stopped, or after a partial apply.
wait_for_ssh() {
    local name=$1 ip=$2
    printf 'waiting for ssh on %s (%s) ' "$name" "$ip"
    for _ in $(seq 1 60); do
        if nc -z -w 2 "$ip" 22 2>/dev/null; then
            echo "up"
            return 0
        fi
        printf '.'
        sleep 5
    done
    echo " TIMEOUT"
    return 1
}

failed=""
while IFS=$'\t' read -r name ip; do
    wait_for_ssh "$name" "$ip" || failed="$failed $name"
done < <(tofu -chdir=terraform output -json node_ips | jq -r 'to_entries[] | "\(.key)\t\(.value)"')

if [ -n "$failed" ]; then
    echo "Error: nodes did not become reachable:$failed"
    exit 1
fi

echo "All nodes up. Next:"
echo "  ansible-playbook site.yml -i inventory/minimal-cluster/hosts.ini"
```

- [ ] **Step 2: Make it executable and verify with linters**

Run:
```bash
chmod +x provision.sh && bash -n provision.sh && shellcheck provision.sh
```
Expected: no output from `bash -n`; shellcheck clean (or explain/fix any finding — do not suppress with directives without a comment saying why).

- [ ] **Step 3: Commit**

```bash
git add provision.sh
git commit -m "feat: add provision.sh to apply tofu and wait for node SSH

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: minimal-cluster Ansible inventory (gitignored — no commit)

**Files:**
- Create: `inventory/minimal-cluster/hosts.ini`
- Create: `inventory/minimal-cluster/group_vars/all.yml` (copy of `inventory/codingworks-cluster/group_vars/all.yml` with 3 edits)
- Create: `inventory/minimal-cluster/group_vars/proxmox.yml` (copy, unchanged)

**Interfaces:**
- Consumes: node IPs from Global Constraints.
- Produces: `inventory/minimal-cluster/hosts.ini` — used by Task 7's `ansible-playbook -i`.

- [ ] **Step 1: Copy the reference inventory**

```bash
cp -R inventory/codingworks-cluster inventory/minimal-cluster
```

- [ ] **Step 2: Write `inventory/minimal-cluster/hosts.ini`**

Replace the file contents entirely with:

```ini
[all:vars]
ansible_connection=ssh
ansible_port=22
ansible_private_key_file=~/.ssh/id_ed25519
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_ssh_user=ansibleuser

[master]
192.168.30.121
192.168.30.122
192.168.30.123

[node]
192.168.30.124
192.168.30.125

[k3s_cluster:children]
master
node
```

- [ ] **Step 3: Edit `inventory/minimal-cluster/group_vars/all.yml` — exactly 3 changes**

1. `apiserver_endpoint: 192.168.30.222` → `apiserver_endpoint: 192.168.30.223`
2. `flannel_iface: eth0` → `flannel_iface: ens18` (Ubuntu cloud-image VMs on Proxmox name the virtio NIC `ens18`; Task 7 Step 3 verifies this against a real VM before Ansible runs)
3. `k3s_token: ...` → a fresh alphanumeric token, e.g. output of `openssl rand -hex 16`

Leave everything else as-is — in particular `metal_lb_ip_range: 192.168.30.31-192.168.30.60` is already the agreed range.

- [ ] **Step 4: Verify inventory parses and is NOT tracked by git**

Run:
```bash
ansible-inventory -i inventory/minimal-cluster/hosts.ini --list | jq '.master.hosts, .node.hosts'
git check-ignore inventory/minimal-cluster/hosts.ini && echo "correctly gitignored"
```
Expected: masters `["192.168.30.121", "192.168.30.122", "192.168.30.123"]`, nodes `["192.168.30.124", "192.168.30.125"]`, and `correctly gitignored`.

No commit for this task (directory is gitignored by design).

---

### Task 6: Documentation

**Files:**
- Create: `terraform/README.md`
- Modify: `docs/node.md` (replace manual template/clone sections)

**Interfaces:**
- Consumes: everything above; no downstream consumers.

- [ ] **Step 1: Create `terraform/README.md`**

```markdown
# Proxmox VM Provisioning (OpenTofu)

Provisions the VMs for the k3s cluster: a Ubuntu 24.04 cloud-image template
(VM 920) and five full clones — cp1–cp3 (192.168.30.121–123) and wk1–wk2
(192.168.30.124–125). Cloud-init sets static IPs, creates `ansibleuser` with
your SSH key, and installs qemu-guest-agent on first boot.

## One-time Proxmox setup

1. **API token** — run on the Proxmox host shell:

   ```bash
   pveum role add TerraformProv -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify SDN.Use VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt User.Modify"
   pveum user add terraform@pve
   pveum aclmod / -user terraform@pve -role TerraformProv
   pveum user token add terraform@pve provision --privsep=0
   ```

   Save the printed token value — it is shown once.

2. **Snippets storage** — enable the `Snippets` content type on the `local`
   datastore: Datacenter → Storage → local → Edit → Content → check Snippets.
   (Used for the cloud-init vendor-data file.)

3. **SSH agent** — snippet upload happens over SSH as root. Ensure
   `ssh root@<proxmox-ip>` works and your key is loaded (`ssh-add -l`).

## Usage

```bash
export PROXMOX_VE_ENDPOINT=https://<proxmox-ip>:8006/
export PROXMOX_VE_API_TOKEN='terraform@pve!provision=<uuid>'

# from the repo root — applies tofu and waits for SSH on all nodes
./provision.sh

# then deploy k3s
ansible-playbook site.yml -i inventory/minimal-cluster/hosts.ini
```

Direct tofu use: `tofu -chdir=terraform plan|apply|destroy`.

Node sizing, IPs, and VM IDs live in `terraform.tfvars`. Adding a node is one
more entry in the `nodes` map; removing one shows the destroy in the plan
before anything happens.

## State

State is a local `terraform.tfstate` (gitignored). Back it up if you care
about it; losing it means re-importing or re-creating resources. To move
state to the homelab MinIO later, add an `s3` backend block and run
`tofu init -migrate-state`.
```

- [ ] **Step 2: Update `docs/node.md`**

Replace the sections `### Create Proxmox Template`, `### Configure the template`, and `### Post clone steps` (from the `## Manual setup - Control Plane` heading through the line before `## Manual setup - Worker Nodes`) with:

```markdown
## Control Plane and Worker VMs (OpenTofu)

VM provisioning is automated — see `terraform/README.md`. In short:

```bash
export PROXMOX_VE_ENDPOINT=https://<proxmox-ip>:8006/
export PROXMOX_VE_API_TOKEN='terraform@pve!provision=<uuid>'
./provision.sh
```

This builds template VM 920 from the Ubuntu 24.04 minimal cloud image and
clones cp1–cp3 (192.168.30.121–123) and wk1–wk2 (192.168.30.124–125).
Cloud-init assigns static IPs and installs qemu-guest-agent, so neither
`static-ip.sh` nor manual post-clone steps are needed for VMs.
```

Keep `## Manual setup - Worker Nodes` and everything after it unchanged (it documents physical machines). In the `## K3s deployment` section, update the deploy instruction to `ansible-playbook site.yml -i inventory/minimal-cluster/hosts.ini` and note that `static-ip.sh` applies to physical nodes only.

- [ ] **Step 3: Verify docs render sanely**

Run:
```bash
grep -n "provision.sh\|terraform/README" docs/node.md terraform/README.md | head
```
Expected: cross-references present; eyeball the diff of `docs/node.md` to confirm only the manual-template sections were replaced.

- [ ] **Step 4: Commit**

```bash
git add terraform/README.md docs/node.md
git commit -m "docs: replace manual Proxmox template process with OpenTofu workflow

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Acceptance — real apply and cluster deploy (requires Proxmox credentials)

**Files:** none (operational verification)

**Interfaces:**
- Consumes: everything above. Requires the operator to have completed the one-time setup in `terraform/README.md` and exported the env vars.

- [ ] **Step 1: Plan and review**

Run:
```bash
tofu -chdir=terraform plan
```
Expected: `Plan: 8 to add, 0 to change, 0 to destroy.` (1 download file + 1 snippet + 1 template + 5 nodes). MUST NOT touch any existing VM — if the plan shows changes to anything but these 8 resources, STOP and investigate.

- [ ] **Step 2: Provision**

Run:
```bash
./provision.sh
```
Expected: apply completes (template build then 5 clones; first boot installs the agent, so allow several minutes), then `waiting for ssh on cp1 (192.168.30.121) up` … for all 5 nodes, ending with the ansible-playbook next-step hint.

- [ ] **Step 3: Verify SSH, sudo, agent, and interface name**

Run:
```bash
for ip in 121 122 123 124 125; do
  ssh -o StrictHostKeyChecking=no ansibleuser@192.168.30.$ip \
    'hostname && sudo -n true && systemctl is-active qemu-guest-agent && ip -o link show | grep -v lo | cut -d: -f2'
done
```
Expected per node: hostname `k3s-cpN`/`k3s-wkN`, no sudo password prompt, `active`, and interface name `ens18`. **If the interface is not `ens18`**, set `flannel_iface` in `inventory/minimal-cluster/group_vars/all.yml` to the actual name before proceeding.

- [ ] **Step 4: Verify idempotency**

Run:
```bash
tofu -chdir=terraform plan
```
Expected: `No changes. Your infrastructure matches the configuration.`

- [ ] **Step 5: Deploy k3s**

Run:
```bash
ansible-playbook site.yml -i inventory/minimal-cluster/hosts.ini
```
Expected: playbook completes; then:
```bash
ping -c 2 192.168.30.223
KUBECONFIG=./kubeconfig kubectl get nodes
```
Expected: VIP answers; 5 nodes `Ready` (3 control-plane/etcd/master, 2 workers).
