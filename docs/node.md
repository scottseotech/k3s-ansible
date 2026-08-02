# K3S Setup

## Architecture Overview

- **kube-vip**: Virtual IP load balancer for K8s API across control plane nodes
- **Proxmox Host**: Virtualizes 3 K3s control plane nodes for high availability
- **Physical Workers**: 2 bare-metal nodes for workload execution
- **TrueNAS**: Provides persistent storage via iSCSI (Democratic CSI)
- **BackBlaze**: Off-site backup destination for disaster recovery

```mermaid
graph TB
    VIP{{"kube-vip<br/>192.168.30.222"}}

    subgraph Proxmox["Control Plane (Proxmox VMs)"]
        direction LR
        CP1["CP-1<br/><small>192.168.30.111</small>"]
        CP2["CP-2<br/><small>192.168.30.112</small>"]
        CP3["CP-3<br/><small>192.168.30.113</small>"]
    end

    subgraph Physical["Worker Nodes (Physical)"]
        direction LR
        W1["Worker-1<br/><small>192.168.30.101</small>"]
        W2["Worker-2<br/><small>192.168.30.102</small>"]
    end

    NAS[("TrueNAS<br/>192.168.30.224<br/><small>iSCSI Storage</small>")]
    BB(("BackBlaze<br/><small>Off-site Backup</small>"))

    VIP -.->|"Virtual IP<br/>Load Balancer"| Proxmox

    CP1 ---|Quorum| CP2
    CP2 ---|Quorum| CP3
    CP3 ---|Quorum| CP1

    Proxmox ==>|Schedules Workloads| Physical
    Physical ==>|iSCSI PVs| NAS
    NAS -.->|Replicate| BB

    style VIP fill:#3d5a3d,stroke:#9ccc65,stroke-width:4px,color:#fff,stroke-dasharray: 5 5
    style Proxmox fill:#1e3a5f,stroke:#64b5f6,stroke-width:3px,color:#e0e0e0
    style Physical fill:#4a2d5e,stroke:#ba68c8,stroke-width:3px,color:#e0e0e0
    style NAS fill:#5d4a2d,stroke:#ffb74d,stroke-width:3px,color:#e0e0e0
    style BB fill:#2d4a3d,stroke:#66bb6a,stroke-width:3px,color:#e0e0e0
    style CP1 fill:#2c5282,stroke:#90caf9,color:#fff,stroke-width:2px
    style CP2 fill:#2c5282,stroke:#90caf9,color:#fff,stroke-width:2px
    style CP3 fill:#2c5282,stroke:#90caf9,color:#fff,stroke-width:2px
    style W1 fill:#5a2d75,stroke:#ce93d8,color:#fff,stroke-width:2px
    style W2 fill:#5a2d75,stroke:#ce93d8,color:#fff,stroke-width:2px
```
## Manual setup - Control Plane 

### Create Proxmox Template

Look at this [video](https://www.youtube.com/watch?v=MJgIm03Jxdo&t=4s) for reference

Click **"Create VM"** button on upper righthand corner and configure

=== "**General**"
    * VM ID: `900` (high number to show at bottom of list)

=== "**OS**"
    * Select `Do not use any media`

=== "**System**"
    * Enable `Qemu Agent`

=== "**Disk**"
    * Click trash icon to delete the disk

=== "**CPU**"
    * Cores: `2`

=== "**Memory**"
    * RAM: `2048 MiB`

=== "**Network**"
    * Use default settings

=== "**Confirm**"
    * Click `Finish`

### Configure the template

* Click on **Hardware** then click on **Add** then **Cloud Init Drive**

```
User           : ansibleuser
Password       : your password
SSH public key : copy and paste your ssh public key
IP Config(net0): select DHCP
```

* Click on **Regenerate Image**

* Run the following in the Proxmox shell

```
wget https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img

mv ubuntu-24.04-minimal-cloudimg-amd64.img ubuntu-24.04.qcow2

qm set 900 --serial0 socket --vga serial0

qemu-img resize ubuntu-24.04.qcow2 32G

qm importdisk 900 ubuntu-24.04.qcow2 local-lvm
```

* Go back to **Hardware** and click on **Unused disk** or something. Select **Discard** then select **SSD emulation**

* Right click on the template then convert to template

* Clone with **Mode: Full Clone**

### Post clone steps

* Install qemu-guest-agent. The qemu agent enables advanced communication between guest and host. i.e. graceful shutdown. freezing of file system during backup and snapshot.

```
apt-get install qemu-guest-agent
```

## Manual setup - Worker Nodes

* Use Ubuntu 24.04 server minimal ISO image
* Create a user `ansibleuser`

### Setup Passwordless SSH Auth
```bash
ssh-copy-id ansibleuser@192.168.30.102
```

### Root passwordless
```bash
sudo su - root
cd /root
cp -r /home/ansibleuser/.ssh /root
```

### Add user to sudoers
```bash
visudo -f /etc/sudoers.d/ansibleuser

ansibleuser ALL=(ALL) NOPASSWD:ALL
```

### Create local ssh config
```bash
Host k3s2
 HostName 192.168.30.102
 User ansibleuser
```

## K3s deployment

* Open up `https://github.com/scottseotech/k3s-ansible`
* check out minimal-nodes-setup branch

### Static IP and custom MTU

* cd into k3s-ansible repo
* execute static-ip.sh to set interface name and static ip
* site.yaml playbook configuration expects same interface name for all nodes
* Configure inventory/my-cluster/group_vars/all.yml
* run deploy.sh

* ping 192.168.30.222 verify vip is working
* mv kubeconfig ~/.kube/config
* execute scripts/create-ns.sh
* kubectl apply -f ./todo-secrets.yaml

LincStation N2 Notes:

Installation Issue
`Error can't find partition 2 on mmcblk0`

sed -i s/tries=30/tries=130/ /usr/lib/python3/dist-packages/truenas_installer/install.py