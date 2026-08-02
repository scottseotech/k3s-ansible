#!/bin/bash
set -eo pipefail

cd "$(dirname "$0")"

usage() {
    echo "Usage: $0 <inventory-name>"
    echo ""
    echo "  <inventory-name>  Folder name under inventory/ (e.g. minimal-cluster)"
    echo ""
    echo "Available inventories:"
    for dir in inventory/*/; do
        name=$(basename "$dir")
        [ "$name" = "sample" ] && continue
        echo "  $name"
    done
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

inventory="inventory/$1/hosts.ini"

if [ ! -f "$inventory" ]; then
    echo "Error: $inventory not found"
    echo ""
    usage
fi

ansible-playbook reset.yml -i "$inventory"
