#!/bin/bash

if [[ "$(whoami)" != "root" ]]; then
  echo "must run as root"
  exit 1
fi

# networking
echo "192.168.33.13 ldapserver" >> /etc/hosts
echo "192.168.33.15 slurmctld" >> /etc/hosts
echo "192.168.33.16 login" >> /etc/hosts
echo "192.168.33.17 slurmd" >> /etc/hosts

# install packaged slurm, singularity
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt install slurmd munge -y
apt-get install /vagrant/resources/singularity-ce_3.10.2-focal_amd64.deb -y

# bring in config
cp /vagrant/resources/slurm.conf /etc/slurm-llnl/
cp /vagrant/resources/cgroup.conf /etc/slurm-llnl/

# set up munge with common, insecure key
cp /vagrant/resources/munge.key /etc/munge/munge.key 
systemctl restart munge

# start the services and set them to run at startup
systemctl enable slurmd
systemctl start slurmd

# make a user
# expect UID/GID 1002 - can use this to create a determined user and link
adduser --disabled-password --gecos "" hpcuser1

# mount NFS share
apt-get install nfs-common -y
mkdir -p /shared && chmod 777 /shared
echo "slurmctld:/shared /shared nfs defaults 0 0" >> /etc/fstab

while ! timeout 10 mount /shared; do
  echo "unable to mount NFS share, will try again..."
  sleep 1s
done
