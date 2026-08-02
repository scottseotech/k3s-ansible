# Proxmox VM Provisioning with OpenTofu — Design

**Date**: 2026-08-02
**Status**: Approved pending review
**Branch**: minimal-nodes-setup

## Goal

Automate the full lifecycle (create/modify/destroy) of the Proxmox VMs that back a
new k3s cluster, so a cluster can be stood up from a bare Proxmox host with two
commands: `provision.sh` (VMs) then `deploy.sh` (k3s via existing Ansible).

The existing cluster (VIP 192.168.30.222, nodes .111–.113 and physical workers
.101–.102) is **not touched**. This provisions a new, parallel node set.

## Decision

Use **OpenTofu with the `bpg/proxmox` provider** for the VM layer; Ansible remains
unchanged for OS/k3s configuration. Chosen over `community.general.proxmox_kvm`
because Terraform-style state gives plan/preview before destructive changes,
handles deletions when VMs are removed from config, and detects drift — the
Ansible Proxmox modules do none of these reliably. Packer was rejected as
unnecessary: the existing Ansible roles already handle all OS preparation, so a
plain cloud image template suffices.

## Node Layout

| Name | Role          | IP                | VM ID | Cores | RAM   |
|------|---------------|-------------------|-------|-------|-------|
| cp1  | control plane | 192.168.30.121/24 | 921   | 2     | 4 GB  |
| cp2  | control plane | 192.168.30.122/24 | 922   | 2     | 4 GB  |
| cp3  | control plane | 192.168.30.123/24 | 923   | 2     | 4 GB  |
| wk1  | worker        | 192.168.30.124/24 | 924   | 4     | 8 GB  |
| wk2  | worker        | 192.168.30.125/24 | 925   | 4     | 8 GB  |

All five are full clones of a template VM built from the Ubuntu 24.04 minimal
cloud image. VM IDs mirror the IP last octet (92x) and avoid existing VMs and
template ID 900. Sizing is per-node in `terraform.tfvars` and can be changed
later (`tofu plan` will show whether a change is in-place or forces recreation).

### Cluster networking (Ansible side, new inventory)

- New inventory directory: `inventory/minimal-cluster/` (copied from
  `scottseo-cluster`, edited — existing inventories untouched)
- `apiserver_endpoint` (kube-vip VIP): **192.168.30.223**
- `metal_lb_ip_range`: **192.168.30.31–192.168.30.60**
- Verified non-colliding with existing cluster (VIP .222, MetalLB .10–.30)

## Terraform Layout

```
terraform/
├── main.tf            # provider config, image download, template VM, node VMs
├── variables.tf       # nodes map, network, datastore, template settings
├── outputs.tf         # node names → IPs
├── terraform.tfvars   # actual values (committed; contains no secrets)
└── .gitignore         # *.tfstate*, *.auto.tfvars, .terraform/
```

### Provider & authentication

- Provider: `bpg/proxmox` (pinned version).
- API auth via environment variables — never in git:
  - `PROXMOX_VE_ENDPOINT` (e.g. `https://192.168.30.43:8006/`)
  - `PROXMOX_VE_API_TOKEN` (a Proxmox API token with VM admin privileges)
- Provider SSH access to the Proxmox host (existing SSH key) for uploading the
  cloud-init vendor-data snippet. Requires the snippets content type enabled on
  a datastore (one-time Proxmox setting, documented in README).

### Template (replaces manual VM-900 process)

1. `proxmox_virtual_environment_download_file` downloads
   `ubuntu-24.04-minimal-cloudimg-amd64.img` onto the Proxmox datastore.
2. A VM resource with `template = true` (ID 920) builds the template: disk
   imported from the image and resized to 32 G, serial console + serial VGA,
   discard + SSD emulation, qemu-agent flag enabled, cloud-init drive.

The manual steps in `docs/node.md` (UI clicking, `qm importdisk`, etc.) are
retired for VMs; a new image version is a variable change + `tofu apply`.

### Node VMs

A single `nodes` map variable (name → vmid, ip, cores, memory) drives
`for_each` clone resources. Each clone's cloud-init sets:

- Static IP + gateway (192.168.30.1) + DNS — no DHCP; `static-ip.sh` is no
  longer needed for VMs (remains for physical machines)
- User `ansibleuser` with the operator's SSH public key (passwordless sudo via
  cloud-init sudo directive)
- Vendor-data snippet: install `qemu-guest-agent` on first boot and start it
  (retires the manual post-clone step)

Adding a node later = one more map entry; removing one = delete the entry and
`tofu plan` shows the destroy for confirmation.

### State

Local `terraform.tfstate`, gitignored. Acceptable for a single operator.
Optional later migration: S3 backend pointed at the homelab MinIO (one `backend`
block + `tofu init -migrate-state`); noted in README, not implemented now.

## Workflow

```
export PROXMOX_VE_ENDPOINT=... PROXMOX_VE_API_TOKEN=...
./provision.sh          # tofu apply (interactive approve) + wait for SSH on all node IPs
./deploy.sh             # unchanged — ansible-playbook site.yml (new inventory)
```

`provision.sh` (repo root):
1. `tofu -chdir=terraform apply` — plan shown, user approves; nothing auto-applies.
2. Poll each node IP until SSH answers (timeout with clear error naming the
   stragglers).

Error handling: tofu failures stop the script before the SSH wait; SSH-wait
timeout exits non-zero so a chained `provision.sh && deploy.sh` halts. Re-running
either script is safe (both are idempotent).

## Documentation Changes

- `docs/node.md`: replace the manual template/clone sections with a short
  "Provisioning VMs (OpenTofu)" section; keep physical-worker instructions.
- `terraform/README.md` (or a section in repo README): one-time setup — API
  token creation, snippets datastore, `tofu init`.

## Testing

- `tofu validate` + `tofu plan` reviewed before first apply.
- Acceptance: from a Proxmox host with no template and no 92x VMs,
  `provision.sh` produces 5 running VMs answering SSH as `ansibleuser` at
  .121–.125 with qemu-guest-agent active; then `deploy.sh` with
  `inventory/minimal-cluster` brings up k3s with VIP .223 reachable.
- Re-run of `tofu plan` after apply shows no changes (clean idempotency).

## Out of Scope

- Generating `hosts.ini` from tofu outputs (IPs are static in both places)
- Packer / golden images
- Managing existing VMs, physical workers, or the Proxmox host itself
- Remote state backend (documented as future option only)
- Decommissioning the old cluster
