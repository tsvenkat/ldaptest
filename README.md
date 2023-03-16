# ldaptest
A vagrant environment that runs a OpenLDAP server along with a sample of SLURM cluster VMs to use it

## Prerequisites
```
Vagrant - version 2.3.4
VirtualBox - version 7.0
vagrant plugin install vagrant-vbguest
```

## To bring up the VMs 
```
cd ldaptest
vagrant up
```

## To work with individual VMs
```
vagrant ssh slurmctld
sinfo
ssh Robert@slurmctld
```

> For password, refer to the file resources/openldap.sh

> For ldapsearch/modify example commands, refer to resources/setup_sssd.sh

## What does vagrant up do?
- [x] Setup a OpenLDAP based VM
- [x] Initialize a self-signed CA certificate
- [x] Sign a certificate for the ldapserver node using the CA cert
- [x] Configure OpenLDAP with some sample users (Robert, Theon) and groups (admin, oper)
- [x] Bring up a SLURM cluster with 3 VMs
- [x] A slurmctld node
- [x] A slurmd node
- [x] A login node
- [x] The slurmctld node also hosts a NFS share - "/shared"
- [x] The home folder for users will be under "/shared/home"
- [x] SLURM config file is preset with 3 partitions (charlie, tango, sierra). All use the single slurmd node

### Key config files
```
ldapserver:
  /etc/openldap/ldap.conf
  /etc/sysconfig/ldap
  
slurmctld (and other nodes):
  /etc/sssd/sssd.conf
  /etc/sshd/sshd_conf
```
