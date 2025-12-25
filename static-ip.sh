#!/bin/bash -e

# set -x

export ANSIBLE_STDOUT_CALLBACK=debug
export ANSIBLE_ROLES_PATH=./roles:../roles:~/.ansible/roles

# Function to display usage
usage() {
    echo "Usage: $0 <target_host_ip> <new_static_ip> [interface] [gateway]"
    echo ""
    echo "Arguments:"
    echo "  target_host_ip   IP address of the target host (required)"
    echo "  new_static_ip    New static IP address to assign (required)"
    echo "  interface        Network interface name (optional, default: eth0)"
    echo "  gateway          Default gateway address (optional, default: 192.168.30.1)"
    echo ""
    echo "Example:"
    echo "  $0 192.168.30.106 192.168.30.50"
    echo "  $0 192.168.30.106 192.168.30.50 eth1 192.168.30.254"
    exit 1
}

# Check if required arguments are provided
if [ $# -lt 2 ]; then
    echo "Error: Missing required arguments"
    echo ""
    usage
fi

# Parse arguments
ip_address=$1
static_ip=$2
iface=${3:-eth0}
gateway=${4:-192.168.30.1}

cat ./hosts.tpl > hosts
echo ${ip_address} >> hosts 

ansible-playbook -i hosts -e "static_ip=${static_ip} iface=${iface} gateway=${gateway}" static-ip.yml

rm -f hosts

