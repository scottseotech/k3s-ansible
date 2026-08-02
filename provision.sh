#!/bin/bash
set -eo pipefail

cd "$(dirname "$0")"

for cmd in tofu jq nc; do
    if ! command -v "$cmd" >/dev/null; then
        echo "Error: required command '$cmd' not found in PATH"
        exit 1
    fi
done

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

node_list=$(tofu -chdir=terraform output -json node_ips | jq -r 'to_entries[] | "\(.key)\t\(.value)"')
if [ -z "$node_list" ]; then
    echo "Error: could not read node_ips from tofu output"
    exit 1
fi

failed=""
while IFS=$'\t' read -r name ip; do
    wait_for_ssh "$name" "$ip" || failed="$failed $name"
done <<< "$node_list"

if [ -n "$failed" ]; then
    echo "Error: nodes did not become reachable:$failed"
    exit 1
fi

echo "All nodes up. Next:"
echo "  ansible-playbook site.yml -i inventory/minimal-cluster/hosts.ini"
