[all:vars]
ansible_connection=ssh
ansible_port=22
ansible_private_key_file=~/.ssh/id_ed25519
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_ssh_user=ansibleuser

[nodes]
