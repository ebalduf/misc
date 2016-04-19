#!/usr/bin/env bash

# This script assumes 
#  1) that the template is at 172.27.162.239 
#  2) the template has a  hostname of balduf-centos.pm.solidfire.net
#  3) that the script is run from where local.conf lives

BASEIP=172.27.162.
DOMAINNAME=.pm.solidfire.net
NAMESERVER=172.27.1.251
EXTERNAL_NETWORK_CIDR=172.27.162.0/24
EXTERNAL_NETWORK_GATEWAY=${BASEIP}254
TENANT_NETWORK_CIDR=192.168.1.0/24
TENANT_NETWORK_GATEWAY=192.168.1.254

if [[ $PWD == *"devstack"* ]]
then
  echo "WARNING! This script should not be run from devstack!";
  exit 1
fi

if [ "$#" -ne 2 ]; then
  echo "Usage: ChangeIP IPaddr Hostname"
  echo "  where IPaddr is last Octet"
  echo "  and Hostname is short hostname (.pm.solidfire.net will be added)"
  exit 1
fi

if [ "$1" -lt 240 -o "$1" -gt 250 ]; then
   echo "IP addr must be between 240 - 250"
   exit 1
fi

SHORTHOSTNAME=$2
MYIP=$1
LONGHOSTNAME=${2}${DOMAINNAME}
IPADDR=${BASEIP}${1}
START=$(expr \( \( ${MYIP} - 240 \) \* 10 \) + 100 )
END=$(expr $START + 9)
FLOATING_IP_START=${BASEIP}${START}
FLOATING_IP_END=${BASEIP}${END}

echo $LONGHOSTNAME $SHORTHOSTNAME $IPADDR
echo "floating IP range: " $FLOATING_IP_START " -> " $FLOATING_IP_END

# edit the network file

cat /etc/sysconfig/network-scripts/ifcfg-eno16780032 | sed "s/172.27.162.239/${IPADDR}/g" > /tmp/ifcfg-enoeno16780032
sudo cp /tmp/ifcfg-enoeno16780032 /etc/sysconfig/network-scripts/ifcfg-eno16780032

# edit the hosts file

cat /etc/hosts | sed "/172.27.162.239/d" > /tmp/hosts
echo "${IPADDR} ${LONGHOSTNAME} ${SHORTHOSTNAME}" >> /tmp/hosts
sudo cp /tmp/hosts /etc/hosts

# edit the local.conf file

SHORTNAME=$(echo ${SHORTHOSTNAME} | awk '{n=split($1,fields,"-"); print fields[n]}')
cat local.conf | sed "s/172.27.162.239/${IPADDR}/g" | sed "s/sf_account_prefix=balduf-liberty/sf_account_prefix=balduf-${SHORTNAME}/g" > /tmp/local.conf
cp /tmp/local.conf local.conf

# change the hostname

sudo hostnamectl set-hostname ${LONGHOSTNAME}

# reboot

sudo reboot

