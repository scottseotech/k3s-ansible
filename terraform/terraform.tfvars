proxmox_node = "pve" # CHANGE to your Proxmox node name (UI sidebar)

nodes = {
  cp1 = { vmid = 921, ip = "192.168.30.121/24", cores = 2, memory = 4096 }
  cp2 = { vmid = 922, ip = "192.168.30.122/24", cores = 2, memory = 4096 }
  cp3 = { vmid = 923, ip = "192.168.30.123/24", cores = 2, memory = 4096 }
  wk1 = { vmid = 924, ip = "192.168.30.124/24", cores = 4, memory = 8192 }
  wk2 = { vmid = 925, ip = "192.168.30.125/24", cores = 4, memory = 8192 }
}
