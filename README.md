# ldaptest
A vagrant environment that runs a OpenLDAP server along with a sample of SLURM cluster VMs to use it

# Prerequisites
Vagrant
VirtualBox
vagrant plugin install vagrant-vbguest

# To bring up the VMs 
cd ldaptest
vagrant up

# To work with individual VMs
vagrant ssh slurmctld
sinfo

ssh Robert@slurmctld
# For password, refer to the openldap.sh file
