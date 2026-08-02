# TrueNAS CSI driver
The documentation on github repo is almost complete

* We are using freenas-api-iscsi csi driver
* Following this [link](https://jonathangazeley.com/2021/01/05/using-truenas-to-provide-persistent-storage-for-kubernetes/) for JUST setting up the TrueNAS Scale iSCSI 
* TrueNAS ip set up requires /24 for server ip
* MTU set up to 9000
* Storage (cloud-storage)- 1 pool 1 VDEV two disks mirror. all others are optional.
* Datasets (k8s-volumes) -  Generic dataset preset, make sure to set quota 2 Tib for parent and child datasets 
* Shares - Portal 0.0.0.0:3260, Initiators Groups 1, Allow all initiators
* Advanced - Set Allowed IP 0.0.0.0/0
* System > Services - Turn on NFS, iSCSI, NFS, SSH with "start automatically"

## K8S worker node setup
```
# This is the snippet from github repo
sudo apt-get install -y open-iscsi lsscsi sg3-utils multipath-tools scsitools

# Enable multipathing
sudo tee /etc/multipath.conf <<-'EOF'
defaults {
    user_friendly_names yes
    find_multipaths yes
}
EOF

sudo systemctl enable multipath-tools.service
sudo service multipath-tools restart

# Ensure that open-iscsi and multipath-tools are enabled and running
sudo systemctl status multipath-tools
sudo systemctl enable open-iscsi.service
sudo service open-iscsi start
sudo systemctl status open-iscsi
```

## K8S setup
Add the helm charts
```
helm repo add democratic-csi https://democratic-csi.github.io/charts/
helm repo update
```

https://github.com/democratic-csi/democratic-csi/issues/479
we need to use legacy version(24.10.2.1) for now

make sure the following matches the values in TrueNas Shares
```
  - targetGroupPortalGroup: 3
    # get the correct ID from the "initiators" section in the UI
    targetGroupInitiatorGroup: 6
```

deleting the last pvc ends up triggering deletion of initiators group in TrueNAS. This seems like a bug. Therefore, don't delete the last pvc.

```
heml show values democratic-csi/democratic-csi > democratic-csi-default-values.yaml 

helm template truenas-csi democratic-csi/democratic-csi --namespace democratic-csi -f ./democratic-csi-values.yaml > all-resources-democratic-csi.yaml

k delete -n democratic-csi -f ./all-resources-democratic-csi.yaml

kubectl apply -n democratic-csi -f ./all-resources-democratic-csi.yaml
```