# Proxmox VM Provisioning (OpenTofu)

Provisions the VMs for the k3s cluster: a Ubuntu 24.04 cloud-image template
(VM 920) and five full clones — cp1–cp3 (192.168.30.121–123) and wk1–wk2
(192.168.30.124–125). Cloud-init sets static IPs, creates `ansibleuser` with
your SSH key, and installs qemu-guest-agent on first boot.

## One-time Proxmox setup

1. **API token** — run on the Proxmox host shell:

   ```bash
   pveum role add TerraformProv -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify SDN.Use VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt User.Modify"
   pveum user add terraform@pve
   pveum aclmod / -user terraform@pve -role TerraformProv
   pveum user token add terraform@pve provision --privsep=0
   ```

   Save the printed token value — it is shown once.

2. **Snippets storage** — enable the `snippets` content type on the `local`
   datastore (used for the cloud-init vendor-data file). From the Proxmox shell:

   ```bash
   # --content replaces the list, so keep the existing types and add snippets
   pvesm set local --content iso,vztmpl,backup,snippets
   ```

   Or in the UI: Datacenter → Storage → **local** (type Directory, not
   local-lvm — LVM storage cannot hold snippets and won't offer the option) →
   Edit → Content → add Snippets.

3. **SSH agent** — snippet upload happens over SSH as root. Ensure
   `ssh root@<proxmox-ip>` works and your key is loaded (`ssh-add -l`).

## Usage

```bash
export PROXMOX_VE_ENDPOINT=https://<proxmox-ip>:8006/
export PROXMOX_VE_API_TOKEN='terraform@pve!provision=<uuid>'

# from the repo root — applies tofu and waits for SSH on all nodes
./provision.sh

# then deploy k3s
./deploy.sh minimal-cluster
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
