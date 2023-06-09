#!/bin/sh

user=`whoami`
home=`getent passwd $user | awk -F: '{print $6}' | tail -1`

if [ "$user" == "nobody" ] ; then 
	echo Not creating SSH keys for user $user
elif [ "$user" == "root" ] ; then
       	:
elif [ `echo $home | wc -w` -ne 1 ] ; then
       	echo cannot determine home directory of user $user
else
       	# echo the home directory for user $user is $home 
	# echo test if home exists and is a dir
       	if [ ! -d $home ]; then
	       	echo cannot access home directory $home
       	else
	       	file=$home/.ssh/id_rsa type=rsa
	       	if [ ! -e $file ] ; then
		       	echo generating ssh file $file ...
		       	ssh-keygen -t $type -N '' -f $file
		fi
	       
		id="`cat $home/.ssh/id_rsa.pub`"
	       	file=$home/.ssh/authorized_keys
	       	if ! grep "^$id\$" $file >/dev/null 2>&1 ; then
		       	echo adding id to ssh file $file
		       	echo $id >> $file
	       	fi
	       	# echo chmod 600 $home/.ssh/authorized_keys*
	       	chmod 600 $home/.ssh/authorized_keys*
    	fi
fi
