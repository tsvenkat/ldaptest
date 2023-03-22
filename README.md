# ldaptest
A vagrant environment that runs a OpenLDAP server along with a sample of SLURM cluster VMs to use it

## Prerequisites
### Install
```
ansible - version 2.6.12 (or later)
Vagrant - version 2.3.4
VirtualBox - version 7.0
```

## To bring up the VMs 
```
git clone git@github.com:/tsvenkat/ldaptest
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

**Note:** There is also a partition "victor", that is allowed only for the group "oper". User Theon is part of this group and so can submit jobs to this partition.

### Key config files
```
ldapserver:
  /etc/openldap/ldap.conf
  /etc/sysconfig/ldap
  
slurmctld (and other nodes):
  /etc/sssd/sssd.conf
  /etc/sshd/sshd_conf
```

## Putting the vagrant environment to use
```
# the nodes slurmctld, login and slurmd all should have now been configured
# with sssd to connect to the ldapserver node for auth, posix attributes and sudo

# ssh to the login node as the vagrant user, for example
vagrant ssh login

# Following searches should not fetch any results
grep "Robert" /etc/passwd
grep "Theon" /etc/passwd
grep "oper" /etc/group

# Following should return results, as they should be from the openldap server
getent passwd Robert
getent passwd Theon
getent group oper
groups Robert
# Note: the groups command may complain that it cannot find a matching group for the
# gid, but that is ok. The default group for the users Robert and Theon was not given a name

# Next, try to login to the same node as user Robert
# Should see a password prompt. Enter Robert123
ssh Robert@login

# Notice that the home directory for the user is "/shared/home/Robert"
# /shared is a nfs mount hosted by the slurmctld VM
# Also notice that there is no ".ssh" folder in that home directory (as it is on a shared mount)

# The same should work for user Theon as well (password: Theon123)

# Next, try to use passwordless key based ssh auth
# The sample users have been configured in the ldapserver with some predefined public keys
# The corresponding generated private keys are stored under the path: /vagrant/generated/sshkeys/<user>/

ssh -i /vagrant/generated/sshkeys/Robert/id_rsa Robert@login

# That should login without any prompt for password
# Same should work for user Theon as well
# Note how there is still no ".ssh" folder in the home directory

# The ldapserver also has been configured with a sudoers group that only the user Robert is part of

ssh -i /vagrant/generated/sshkeys/Robert/id_rsa Robert@login
sudo whoami
# must print "root"

# Try doing sudo for the user "Theon" and it should prompt for a password, hinting that Theon cannot sudo

# As a last feat, let's try to disable PasswordAuthentication in the sshd_config
# Edit the file and set PasswordAuthentication to "no"
sudo vi /etc/ssh/sshd_config

# Restart sshd
sudo systemctl restart sshd

# Now retry the login 
ssh Robert@login
# you should see the connection close immediately

# However, key based auth should still work
ssh -i /vagrant/generated/sshkeys/Robert/id_rsa Robert@login


# More tests (Slurm specific)
# Still logged on to the VM login as user vagrant, look at the list of queues
# It should list 3 queues - tango, charlie and sierra, all in idle state
sinfo

# Next, ssh as user Theon (you may want to re-enable PasswordAuthentication to "yes" first)
ssh Theon@login

# sinfo should list that partition only for the user Theon and allow to submit jobs
# Must not allow other users to use victor
sinfo
```
