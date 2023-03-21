#!/usr/bin/env bash

#sudo -s

if [[ "$(whoami)" != "root" ]]; then
  echo "must run as root"
  exit 1
else
  echo "running as root"
fi

# networking
echo "192.168.33.13 ldapserver" >> /etc/hosts
echo "192.168.33.15 slurmctld" >> /etc/hosts
echo "192.168.33.16 login" >> /etc/hosts
echo "192.168.33.17 slurmd" >> /etc/hosts

## Install openldap
sudo yum -y install openssl openldap compat-openldap openldap-clients openldap-servers openldap-servers-sql openldap-devel
sudo systemctl start slapd.service
sudo systemctl enable slapd.service

# Note:
# To run sssd interactively and debug, first stop the sssd daemon
#   sudo sssd -d 3 -i -c /etc/sssd/sssd.conf
# To send SIGHUP(1), SIGINT(2) and SIGKILL(9) to it, from another terminal
#   sudo kill -2 `pgrep -x sssd`
# Setting debug_level = 0x3ff0 under the domain section in the sssd.conf file helps debug the ldap interactions

# Create a self-signed CA cert and key and then use that to create a cert for the ldapserver
# Make use of SAN to allow client requests that targets multiple IPs for the ldapserver
# For details, refer: https://www.golinuxcloud.com/configure-openldap-with-tls-certificates/

# Generate CA certificate
cd /etc/pki/CA/
touch index.txt
echo 01 > serial

# Create private key for CA certificate
openssl genrsa -out ca.key 4096

# Generate LDAP server certificate

# Configure openssl x509 extension to create SAN certificate
cat << EOF > server_cert_ext.cnf
[v3_ca]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[ req ]
prompt = no
default_bits = 4096
distinguished_name = req_distinguished_name
req_extensions = req_ext

[ req_distinguished_name ]
C= US
ST= Colorado
L= Fort Collins
O= HPE
OU= Greenlake
CN= ldapserver

[ req_ext ]
subjectAltName = @alt_names

[alt_names]
IP.1 = 192.168.33.13
IP.2 = 10.0.2.15
DNS.1 = ldapserver
EOF

# Generate CA Certificate
openssl req -batch -new -x509 -config server_cert_ext.cnf -key ca.key -out ca.cert.pem

# Generate private key for LDAP server certificate and csr
openssl req -nodes -new -config server_cert_ext.cnf -keyout ldapserver.key -out ldapserver.csr
mv ldapserver.key private/
mv ldapserver.csr private/

# Create LDAP server certificate
# the "-batch" is expected to keep it silent and not prompt interactively for confirmation
openssl ca -batch -keyfile ca.key -cert ca.cert.pem -in private/ldapserver.csr -out private/ldapserver.crt -extensions v3_ca -extfile server_cert_ext.cnf

cat index.txt

# Verify the ldap client certificate
openssl verify -CAfile ca.cert.pem private/ldapserver.crt
# Check the content of your ldap server certificate to make sure it contains the list of IP and DNS which we provided earlier
openssl x509 -noout -text -in private/ldapserver.crt | grep -A 1 "Subject Alternative Name"

# Configure LDAPS certificate (using TLS)
cp -v private/ldapserver.crt private/ldapserver.key /etc/openldap/certs/
mkdir -p /etc/openldap/cacerts
cp -v ca.cert.pem /etc/openldap/cacerts/ca.cert.pem

# Copy the cacert to a shared location so other nodes can make use of it
mkdir -p /vagrant/generated
cp -v ca.cert.pem /vagrant/generated/ca.cert.pem

# Securing the LDAP protocol
slapcat -b "cn=config" | egrep "olcTLSCertificateFile|olcTLSCertificateKeyFile"

# modify the values of the olcTLSCertificateFile and olcTLSCertificateKeyFile attributes
cat << EOF > tls7.ldif
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/ldapserver.crt
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/ldapserver.key
-
replace: olcTLSCACertificatePath
olcTLSCACertificatePath: /etc/openldap/cacerts
EOF

# Change the ownership of /etc/openldap/certs and and /etc/openldap/cacerts directory
chown -R ldap:ldap /etc/openldap/certs
chown -R ldap:ldap /etc/openldap/cacerts

ldapmodify -Y EXTERNAL -H ldapi:// -f tls7.ldif

cat << EOF > tls7_1.ldif
dn: cn=config
changetype: modify
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/openldap/cacerts/ca.cert.pem
EOF

ldapmodify -Y EXTERNAL -H ldapi:// -f tls7_1.ldif

# Validate the new values using slapchat
slapcat -b "cn=config" | egrep "olcTLSCertificateFile|olcTLSCertificateKeyFile|olcTLSCACertificateFile"

# Enable TLS in LDAP configuration file.
# edit the /etc/sysconfig/slapd file to add ldaps:/// to the SLAPD_URLS parameter.
#  SLAPD_URLS="ldapi:/// ldap:/// ldaps:///"
cat << EOF > /etc/sysconfig/slapd
# OpenLDAP server configuration
# see 'man slapd' for additional information

# Where the server will run (-h option)
# - ldapi:/// is required for on-the-fly configuration using client tools
#   (use SASL with EXTERNAL mechanism for authentication)
# - default: ldapi:/// ldap:///
# - example: ldapi:/// ldap://127.0.0.1/ ldap://10.0.0.1:1389/ ldaps:///
SLAPD_URLS="ldapi:/// ldap:/// ldaps:///"

# Any custom options
SLAPD_OPTIONS="-s -1"

# Keytab location for GSSAPI Kerberos authentication
#KRB5_KTNAME="FILE:/etc/openldap/ldap.keytab"

loglevel -1
EOF

# Change the below in /etc/openldap/ldap.conf
# TLS_CACERTDIR /etc/openldap/certs
# TLS_CERTDIR  /etc/openldap/certs
# TLS_CACERT /etc/openldap/cacerts/ca.cert.pem
# TLS_REQCERT allow
# create a ldap.conf file
cat << EOF > /etc/openldap/ldap.conf
#
# LDAP Defaults
#

# See ldap.conf(5) for details
# This file should be world readable but not world writable.

#BASE   dc=example,dc=com
#URI    ldap://ldap.example.com ldap://ldap-master.example.com:666

#SIZELIMIT      12
#TIMELIMIT      15
#DEREF          never

TLS_CACERTDIR   /etc/openldap/cacerts
TLS_CERTDIR     /etc/openldap/certs
TLS_CACERT      /etc/openldap/cacerts/ca.cert.pem
TLS_REQCERT     allow

# Turning this off breaks GSSAPI used with krb5 when rdns = false
SASL_NOCANON    on

#TLS_CIPHERS   ECDHE-RSA-AES256-SHA384:AES256-SHA256:!RC4:HIGH:!MD5:!aNULL:!EDH:!EXP:!SSLV2:!eNULL
#TLS_CIPHERS  ALL:!ADH:!EXPORT:!SSLv2:RC4+RSA:+HIGH:+MEDIUM:+LOW
#TLS_PROTOCOL_MIN 3.3

#TLSVerifyclient never
EOF

# Restart slapd service
systemctl restart slapd
systemctl status slapd

# Add a new schema to support ssh public key attribute for the users
cat << EOF > /etc/openldap/schema/openssh-lpk.schema
dn: cn=openssh-lpk,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: openssh-lpk
olcAttributeTypes: ( 1.3.6.1.4.1.24552.500.1.1.1.13 NAME 'sshPublicKey'
    DESC 'MANDATORY: OpenSSH Public key'
    EQUALITY octetStringMatch
    SYNTAX 1.3.6.1.4.1.1466.115.121.1.40 )
olcObjectClasses: ( 1.3.6.1.4.1.24552.500.1.1.2.0 NAME 'ldapPublicKey' SUP top AUXILIARY
    DESC 'MANDATORY: OpenSSH LPK objectclass'
    MAY ( sshPublicKey $ uid )
    )
EOF

ldapadd -Y EXTERNAL -H ldapi:///  -f /etc/openldap/schema/openssh-lpk.schema

# Add schema for sudo capability
cp /vagrant/resources/sudoers.schema /etc/openldap/schema/
ldapadd -Y EXTERNAL -H ldapi:///  -f /etc/openldap/schema/sudoers.schema

# Validate TLS connectivity for LDAP
ldapsearch -x -ZZ
openssl x509 -in /etc/openldap/cacerts/ca.cert.pem -hash


## Configure Openldap -- db.ldif

echo "dn: olcDatabase={2}hdb,cn=config" >> db.ldif
echo "changetype: modify" >> db.ldif
echo "replace: olcSuffix" >> db.ldif
echo "olcSuffix: dc=KingsLanding,dc=Westeros,dc=com" >> db.ldif
echo "" >> db.ldif
echo "dn: olcDatabase={2}hdb,cn=config" >> db.ldif
echo "changetype: modify" >> db.ldif
echo "replace: olcRootDN" >> db.ldif
echo "olcRootDN: cn=ldapadm,dc=KingsLanding,dc=Westeros,dc=com" >> db.ldif
echo "" >> db.ldif
echo "dn: olcDatabase={2}hdb,cn=config" >> db.ldif
echo "changetype: modify" >> db.ldif
echo "replace: olcRootPW" >> db.ldif
password=$(slappasswd -s WinterIsComing)
echo "olcRootPW: $password" >> db.ldif

## Configure Openldap -- base.ldif

echo "dn: dc=KingsLanding,dc=Westeros,dc=com"  >> base.ldif
echo "dc: KingsLanding" >> base.ldif
echo "objectClass: top" >> base.ldif
echo "objectClass: domain" >> base.ldif
echo ""  >> base.ldif
echo "dn: cn=ldapadm,dc=KingsLanding,dc=Westeros,dc=com" >> base.ldif
echo "objectClass: organizationalRole" >> base.ldif
echo "cn: ldapadm" >> base.ldif
echo "description: LDAP Manager" >> base.ldif
echo ""  >> base.ldif
echo "dn: ou=People,dc=KingsLanding,dc=Westeros,dc=com" >> base.ldif
echo "objectClass: organizationalUnit" >> base.ldif
echo "ou: People" >> base.ldif
echo "" >> base.ldif
echo "dn: ou=Group,dc=KingsLanding,dc=Westeros,dc=com" >> base.ldif
echo "objectClass: organizationalUnit" >> base.ldif
echo "ou: Group" >> base.ldif


## Configuure Openldap -- groups.ldif

echo "dn: cn=admin,ou=Group,dc=KingsLanding, dc=Westeros, dc=com" >> groups.ldif
echo "objectClass: top" >> groups.ldif
echo "objectClass: posixGroup" >> groups.ldif
echo "gidNumber: 6001" >> groups.ldif
echo "" >> groups.ldif
echo "dn: cn=oper,ou=Group,dc=KingsLanding, dc=Westeros, dc=com" >> groups.ldif
echo "objectClass: top" >> groups.ldif
echo "objectClass: posixGroup" >> groups.ldif
echo "gidNumber: 6002" >> groups.ldif

## Configure Openldap -- users.ldif

echo "dn: uid=Robert,ou=People,dc=KingsLanding, dc=Westeros, dc=com" >> users.ldif
echo "objectClass: top" >> users.ldif
echo "objectClass: person" >> users.ldif
echo "objectClass: shadowAccount" >> users.ldif
echo "objectClass: posixAccount" >> users.ldif
echo "objectClass: ldapPublicKey" >> users.ldif
echo "cn: Robert" >> users.ldif
echo "sn: Baratheon" >> users.ldif
echo "uid: Robert" >> users.ldif
password=$(slappasswd -s Robert123)
echo "userPassword: $password" >> users.ldif
echo "loginShell: /bin/bash" >> users.ldif
echo "uidNumber: 10001" >> users.ldif
echo "gidNumber: 10001" >> users.ldif
echo "homeDirectory: /home/robert" >> users.ldif
# generate a ssh key pair for the vagrant user and use that for Robert
mkdir -p /vagrant/generated/sshkeys/Robert
ssh-keygen -b 2048 -t rsa -f /vagrant/generated/sshkeys/Robert/id_rsa -q -N ""
# Note: at some point the user Robert should use ssh-copy-id to copy their
# public key to the target system's ~/.ssh/authorized_keys file

sshPublicKey=$(cat /vagrant/generated/sshkeys/Robert/id_rsa.pub)
echo "sshPublicKey: $sshPublicKey" >> users.ldif
echo ""  >> users.ldif
echo "dn: uid=Theon,ou=People,dc=KingsLanding, dc=Westeros, dc=com" >> users.ldif
echo "objectClass: top" >> users.ldif
echo "objectClass: person" >> users.ldif
echo "objectClass: shadowAccount" >> users.ldif
echo "objectClass: posixAccount" >> users.ldif
echo "objectClass: ldapPublicKey" >> users.ldif
echo "cn: Theon" >> users.ldif
echo "sn: Greyjoy" >> users.ldif
echo "uid: Theon" >> users.ldif
password=$(slappasswd -s Theon123)
echo "userPassword: $password" >> users.ldif
echo "loginShell: /bin/bash" >> users.ldif
echo "uidNumber: 10002" >> users.ldif
echo "gidNumber: 10002" >> users.ldif
echo "homeDirectory: /home/theon" >> users.ldif
# generate a ssh key pair for the vagrant user and use that for Theon
mkdir -p /vagrant/generated/sshkeys/Theon
ssh-keygen -b 2048 -t rsa -f /vagrant/generated/sshkeys/Theon/id_rsa -q -N ""
# Note: at some point the user Theon should use ssh-copy-id to copy their
# public key to the target system's ~/.ssh/authorized_keys file

sshPublicKey=$(cat /vagrant/generated/sshkeys/Theon/id_rsa.pub)
echo "sshPublicKey: $sshPublicKey" >> users.ldif

## Configure OpenLdap -- add users to groups
echo "dn: cn=admin,ou=Group,dc=KingsLanding,dc=Westeros,dc=com" >> userGroups.ldif
echo "changetype: modify" >> userGroups.ldif
echo "add: memberUid" >> userGroups.ldif
echo "memberUid: Robert" >> userGroups.ldif
echo ""  >> userGroups.ldif
echo "dn: cn=oper,ou=Group,dc=KingsLanding,dc=Westeros,dc=com" >> userGroups.ldif
echo "changetype: modify" >> userGroups.ldif
echo "add: memberUid" >> userGroups.ldif
echo "memberUid: Theon" >> userGroups.ldif

## Add user Robert to the sudoers group
cat << EOF > sudoUsers.ldif
dn: ou=sudoers,dc=KingsLanding,dc=Westeros,dc=com
objectClass: organizationalUnit
objectClass: top
ou: sudoers

dn: cn=Robert,ou=sudoers,dc=KingsLanding,dc=Westeros,dc=com
objectClass: top
objectClass: sudoRole
cn: Robert
sudoUser: Robert
sudoHost: ALL
sudoRunAsUser: ALL
sudoCommand: ALL
sudoOption: !authenticate
sudoOrder: 2

dn: cn=defaults,ou=sudoers,dc=KingsLanding,dc=Westeros,dc=com
objectClass: top
objectClass: sudoRole
cn: defaults
description: Default sudoOptions go here
sudoOption: env_keep+=SSH_AUTH_SOCK
sudoOrder: 1
EOF

## Apply files to openldap config

sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f db.ldif
sudo cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
sudo chown -R ldap:ldap /var/lib/ldap

sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif
sudo ldapadd -x -w WinterIsComing -D "cn=ldapadm,dc=KingsLanding,dc=Westeros,dc=com" -f base.ldif
sudo ldapadd -x -w WinterIsComing -D "cn=ldapadm,dc=KingsLanding,dc=Westeros,dc=com" -f users.ldif
sudo ldapadd -x -w WinterIsComing -D "cn=ldapadm,dc=KingsLanding,dc=Westeros,dc=com" -f groups.ldif
sudo ldapadd -x -w WinterIsComing -D "cn=ldapadm,dc=KingsLanding,dc=Westeros,dc=com" -f userGroups.ldif
sudo ldapadd -x -w WinterIsComing -D "cn=ldapadm,dc=KingsLanding,dc=Westeros,dc=com" -f sudoUsers.ldif

# Edit openldap acls 

echo "dn: olcDatabase={2}hdb,cn=config" >> access.ldif
echo "changetype: modify" >> access.ldif
echo "replace: olcAccess" >> access.ldif
echo "olcAccess: {0}to * by dn.base="dc=KingsLanding,dc=Westeros,dc=com" manage by * break" >> access.ldif
echo "olcAccess: {1}to attrs=userPassword by self write by anonymous auth" >> access.ldif
echo "olcAccess: {2}to dn.subtree="ou=People,dc=KingsLanding,dc=Westeros,dc=com" by self write by users read" >> access.ldif

sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f access.ldif

# To add the public key for the above users:
# Create a file with the required changes. Example "modUsers.ldif" file below:
# Note: the public key below is just an example. Replace it with the one you created
# The file does 2 changes:
# 1. It adds the "ldapPublicKey" objectClass to the user
# 2. It adds the sshPublicKey attribute to the user and sets it with a value
# More details: https://askubuntu.com/questions/776700/ssh-ldap-authorizedkeyscommand

#dn: uid=Robert,ou=People,dc=KingsLanding,dc=Westeros,dc=com
#changetype: modify
#add: objectClass
#objectClass: ldapPublicKey
#-
#add: sshPublicKey
#sshPublicKey: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDcVwxwQY4vgCJslVe0vc2CRZQ3YPtXyCpU/CfkFjTS/x0zkLQkQ8WRrezi4AmNbyVkk6DhFUTdYcu3y2vBn9ARXMHqWe21yV8VOu9P01zgovdTkLWogcgdEdyV++ugoXLBqjq+FrXc8KTRcxg86jfi4hlbAAqIppa7Jbmv+IPByZTdqieFkMzUM5xPgZXISYrXLii50elWdywjpTKDWkKt4zKV2V9zVz4TzLxUggL0T9SEYAt+f2edaI6tR6XL2f4UM7S70MLjcXHXRvEI1huFLtfzrY0lZqWe1bor/rMye8bBOSl2yL8wP6SKk0j2u5XiUc6vcikZmzyK5VLd7+Hv Robert@ldapserver

# Next, update the user(s) with the public key attribute:
#ldapmodify -x -H ldapi:/// -D "cn=ldapadm, dc=Kingslanding, dc=Westeros, dc=com"  -w WinterIsComing  -f modUsers.ldif
