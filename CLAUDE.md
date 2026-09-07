# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is an Ansible playbook for automated deployment of High Availability (HA) k3s Kubernetes clusters with kube-vip and MetalLB. The playbook supports multiple CNI options (Flannel, Calico, Cilium) and can deploy to various Linux distributions (Debian, Ubuntu, Rocky) on x64, arm64, and armhf architectures.

## Essential Commands

### Initial Setup
```bash
# Install required Ansible collections (REQUIRED before first use)
ansible-galaxy collection install -r ./collections/requirements.yml

# Copy and configure inventory
cp -R inventory/sample inventory/my-cluster
# Edit inventory/my-cluster/hosts.ini with your node IPs
# Edit inventory/my-cluster/group_vars/all.yml with your configuration

# Copy ansible.cfg and update inventory path
cp ansible.example.cfg ansible.cfg
```

### Cluster Operations
```bash
# Deploy k3s cluster
ansible-playbook site.yml -i inventory/my-cluster/hosts.ini

# Remove k3s cluster (NOTE: reboot nodes afterward to destroy VIP)
ansible-playbook reset.yml -i inventory/my-cluster/hosts.ini

# Reboot cluster nodes
ansible-playbook reboot.yml -i inventory/my-cluster/hosts.ini
```

### Testing
```bash
# Run molecule tests (requires molecule and docker)
molecule test

# Test specific scenario
molecule test -s calico
molecule test -s cilium
molecule test -s single_node
```

### Linting and Pre-commit
```bash
# Install pre-commit hooks
pre-commit install

# Run linters manually
yamllint .
ansible-lint
shellcheck *.sh
```

## Architecture

### Playbook Execution Flow (site.yml)

The deployment runs through these phases in order:

1. **Pre-tasks**: Validates Ansible version (requires 2.11+)
2. **Proxmox Preparation** (optional): Configures Proxmox LXC containers if `proxmox_lxc_configure: true`
3. **Node Preparation**: Runs on all k3s_cluster nodes
   - LXC configuration (if applicable)
   - Prerequisites installation (prereq role)
   - k3s binary download (download role)
   - Raspberry Pi specific setup (raspberrypi role)
   - Custom registry configuration (k3s_custom_registries role)
4. **Master Setup**: Deploys k3s servers with etcd in HA mode if multiple masters
5. **Agent Setup**: Deploys k3s agents on worker nodes
6. **Post-Configuration**: CNI deployment (Calico/Cilium), MetalLB or kube-vip cloud provider setup
7. **Kubeconfig Fetch**: Copies kubeconfig to ./kubeconfig in playbook directory

### Role Responsibilities

- **prereq**: System preparation (timezone, kernel modules, packages)
- **download**: Downloads k3s binary to all nodes
- **k3s_server**: Installs k3s server, configures kube-vip for control plane HA
- **k3s_agent**: Installs k3s agent nodes
- **k3s_server_post**: Post-deployment configuration (CNI, load balancer)
- **lxc/proxmox_lxc**: Proxmox LXC container configuration
- **raspberrypi**: Raspberry Pi specific kernel/boot configuration
- **k3s_custom_registries**: Private registry mirror configuration
- **reset**: Completely removes k3s from cluster

### Networking Components

**Control Plane HA**: kube-vip provides a virtual IP (`apiserver_endpoint`) for the control plane, using either ARP (layer2) or BGP.

**Service Load Balancing**: Two options:
- **MetalLB** (default): Provides LoadBalancer service type, supports layer2 or BGP mode
- **kube-vip cloud provider**: Alternative to MetalLB when `kube_vip_lb_ip_range` is set
- **Cilium BGP**: When `cilium_bgp: true`, disables MetalLB and uses Cilium's BGP control plane

**CNI Options** (mutually exclusive):
- **Flannel** (default): Set `flannel_iface` variable
- **Calico**: Uncomment `calico_iface`, supports eBPF dataplane via `calico_ebpf: true`
- **Cilium**: Uncomment `cilium_iface`, supports kube-proxy replacement and Hubble observability

### Inventory Structure

Required inventory groups:
- `[master]`: Control plane nodes (single node = non-HA, multiple nodes = HA with etcd)
- `[node]`: Worker nodes
- `[k3s_cluster:children]`: Must include both master and node groups
- `[proxmox]`: (optional) Proxmox hosts when using LXC containers

### Critical Configuration Variables

Located in `inventory/*/group_vars/all.yml`:
- `apiserver_endpoint`: Virtual IP for control plane (REQUIRED)
- `k3s_token`: Secure token for node communication (REQUIRED)
- `k3s_version`: k3s version to deploy (REQUIRED)
- `ansible_user`: SSH user with passwordless access (REQUIRED)
- CNI interface: One of `flannel_iface`, `calico_iface`, or `cilium_iface`
- Load balancer IP range: `metal_lb_ip_range` or `kube_vip_lb_ip_range`

`apiserver_endpoint` and `metal_lb_ip_range` must BOTH be unique per cluster
when clusters share an L2 segment. See the comment above `metal_lb_ip_range`
in `inventory/sample/group_vars/all.yml` for why the second one is easy to
miss and hard to diagnose.

## Development Notes

### When Modifying Roles

- Role defaults are in `roles/*/defaults/main.yml`
- Role tasks are in `roles/*/tasks/main.yml`
- Templates use Jinja2 syntax with `.j2` extension
- Use `ansible.builtin.*` for built-in modules

### Testing Changes

Use molecule scenarios for testing different configurations:
- `default`: Standard multi-master HA setup with MetalLB
- `calico`: Tests Calico CNI
- `cilium`: Tests Cilium CNI with Hubble
- `kube-vip`: Tests kube-vip cloud provider
- `single_node`: Tests single-node deployment
- `ipv6`: Tests IPv6 configuration

### BGP Configuration Pattern

When adding BGP peer support, follow the merge pattern used for both kube-vip and Cilium:
1. Define individual peer variables (`_peer_asn`, `_peer_address`)
2. Create list variable for additional peers (`_bgp_peers`)
3. Define groups to search for peers (`_groups`)
4. Use merge logic in templates to combine all sources

### Pre-commit Hooks

The repository enforces code quality via pre-commit hooks:
- YAML formatting and linting (yamllint, sort-simple-yaml)
- Ansible linting (ansible-lint)
- Shell script checking (shellcheck)
- Security checks (detect-private-key)
- File format fixes (end-of-file-fixer, trailing-whitespace, remove-crlf)

## Common Patterns

### Conditional CNI Configuration

CNI selection is mutually exclusive via variable definition:
```yaml
# Only define ONE of these:
flannel_iface: eth0  # Uses Flannel (default)
# calico_iface: eth0  # Uses Calico
# cilium_iface: eth0  # Uses Cilium
```

Server args automatically adjust based on CNI choice via template conditionals.

### HA Mode Detection

Cluster automatically switches to HA mode (etcd) when multiple masters are in inventory. The first master initializes with `cluster-init`, subsequent masters join with `--server` flag.

### Master Tainting

Master nodes are tainted with `NoSchedule` when worker nodes exist (`groups['node'] | length >= 1`), prevented via `k3s_master_taint: false`.

## Troubleshooting Resources

See GitHub Discussions: https://github.com/timothystewart6/k3s-ansible/discussions/20

Documentation: https://technotim.live/posts/k3s-etcd-ansible/
