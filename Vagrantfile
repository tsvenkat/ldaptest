# -*- mode: ruby -*-
# vi: set ft=ruby :
#

def provision_with_ansible (config)
  # Download the required ansible roles and run playbook
  config.vm.provision "ansible" do |ansible|
    ansible.playbook          = "provisioning/tasks.yml"
    ansible.galaxy_role_file  = "provisioning/requirements.yml"
    ansible.galaxy_roles_path = "provisioning/roles"
    ansible.galaxy_command    = "ansible-galaxy install --role-file=%{role_file} --roles-path=%{roles_path} --force"
  end
end

Vagrant.configure("2") do |config|

  config.vm.box_download_insecure = true #added by TSV for curl error

  if Vagrant.has_plugin?("vagrant-timezone")
   config.timezone.value = "America/Denver"
  end

  # Uncomment below lines if vagrant-timezone plugin cannot be used
  # set the time for all VMs to be consistent
  #
  #require "time"
  #offset = ((Time.zone_offset(Time.now.zone) / 60) / 60)
  #timezone_suffix = offset >= 0 ? "-#{offset.to_s}" : "+#{offset.to_s}"
  #timezone = "America/Denver"
  #config.vm.provision :shell, :inline => "sudo rm /etc/localtime && sudo ln -s /usr/share/zoneinfo/" + timezone + " /etc/localtime", run: "always" + timezone_suffix
  #

  #config.vm.synced_folder ".", "/vagrant", type: "smb"
  config.vm.box = "geerlingguy/centos7"

  # setup openldap based server first
  config.vm.define "ldapserver", primary: true do |server|
    server.vm.network "forwarded_port", guest: 389, host: 4389
    server.vm.network "forwarded_port", guest: 636, host: 4636
    server.vm.network "private_network", ip: "192.168.33.13"
    server.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
    end
    server.vm.hostname = "ldapserver"
    server.vm.provision "shell", path: "resources/openldap.sh"
    # provision using ansible
    provision_with_ansible server
  end

  # setup a client with ldap tools installed
  config.vm.define "client", autostart: false do |client|
    client.vm.network "forwarded_port", guest: 9090, host: 9090
    client.vm.network "private_network", ip: "192.168.33.14"
    client.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
    end
    client.vm.hostname = "client"
    client.vm.provision "shell", path: "resources/openldap-client.sh"
  end

  # setup Slurm controller
  config.vm.define "slurmctld" do |ctld|
    ctld.vm.box = "ubuntu/focal64"
    ctld.vm.network "private_network", ip: "192.168.33.15"
    ctld.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
      vb.cpus = 2
    end
    ctld.vm.hostname = "slurmctld"
    ctld.vm.provision "shell", path: "resources/setup-sssd.sh"
    ctld.vm.provision "shell", path: "resources/setup-slurmctld.sh"
    # provision using ansible
    provision_with_ansible ctld
  end

  # setup Slurm login node
  config.vm.define "login" do |login|
    login.vm.box = "ubuntu/focal64"
    login.vm.network "private_network", ip: "192.168.33.16"
    login.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
      vb.cpus = 2
    end
    login.vm.hostname = "login"
    login.vm.provision "shell", path: "resources/setup-sssd.sh"
    login.vm.provision "shell", path: "resources/setup-login-node.sh"
    # provision using ansible
    provision_with_ansible login
  end

  # setup Slurmd
  config.vm.define "slurmd" do |slurmd|
    slurmd.vm.box = "ubuntu/focal64"
    slurmd.vm.network "private_network", ip: "192.168.33.17"
    slurmd.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
      vb.cpus = 2
    end
    slurmd.vm.hostname = "slurmd"
    slurmd.vm.provision "shell", path: "resources/setup-sssd.sh"
    slurmd.vm.provision "shell", path: "resources/setup-slurmd.sh"
    # provision using ansible
    provision_with_ansible slurmd
  end


end
