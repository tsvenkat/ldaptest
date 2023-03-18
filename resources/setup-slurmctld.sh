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
apt-get update && apt install slurm-wlm munge -y
apt-get install /vagrant/resources/singularity-ce_3.10.2-focal_amd64.deb -y

# bring in config
cp /vagrant/resources/slurm.conf /etc/slurm-llnl/
cp /vagrant/resources/cgroup.conf /etc/slurm-llnl/

# set up munge with common, insecure key
cp /vagrant/resources/munge.key /etc/munge/munge.key 
systemctl restart munge

# sssd config
mkdir -p /etc/sssd
cp /vagrant/resources/sssd.conf /etc/sssd/
chmod -R 600 /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf
pam-auth-update --enable mkhomedir

# start the services and set them to run at startup
systemctl enable slurmctld
systemctl start slurmctld

# check that partitions are up
if sinfo | grep idle; then
  echo "ok"s
else
  echo "partitions not up (will be up when slurmd nodes are up)"
	#exit 1
fi

# make a user
# expect UID/GID 1002 - can use this to create a local hpc user and link
adduser --disabled-password --gecos "" hpcuser1

# set up NFS share (may not work)
apt-get install nfs-kernel-server -y
mkdir -p /shared 
mkdir -p /shared/home/
chmod -R 777 /shared
echo "/shared *(rw,async,no_wdelay,insecure,no_root_squash,insecure_locks,sec=sys,no_subtree_check)" >> /etc/exports
exportfs -a
