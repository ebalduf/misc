#!/usr/bin/env bash

BASEIP=10.5.1.
MYID=$(hostname -s | cut -d '-' -f 2)
MYIP=${BASEIP}$(expr $MYID + 100)
START=$(expr 109 + \( $MYID \* 8 \) )
END=$(expr $START + 7)
FLOATING_IP_START=${BASEIP}${START}
FLOATING_IP_END=${BASEIP}${END}

NAMESERVER=8.8.8.8
EXTERNAL_NETWORK_CIDR=${BASEIP}0/24
EXTERNAL_NETWORK_GATEWAY=${BASEIP}254
TENANT_NETWORK_CIDR=192.168.1.0/24
TENANT_NETWORK_GATEWAY=192.168.1.254

# Keep track of the devstack directory
TOP_DIR=$(cd $(dirname "$0") && pwd)

# Import common functions
source $TOP_DIR/functions

# Use openrc + stackrc + localrc for settings
source $TOP_DIR/stackrc

# Destination path for installation ``DEST``
DEST=${DEST:-/opt/stack}

## Determine the Public ethernet port name (THIS ONLY WORKS ON FEDORA)
PUBLIC_PORT=`ip a | awk -F': ' '/^3\: /{print $2}'`

##### Add open firewall ports here
sudo iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 6080:6082 -j ACCEPT

### Attach the interface to the external bridge
sudo ovs-vsctl add-port br-ex $PUBLIC_PORT
sudo ip link set dev $PUBLIC_PORT up

if is_service_enabled nova; then

    # Get OpenStack admin auth
    source $TOP_DIR/openrc admin admin

    neutron net-create ext-net --router:external --provider:physical_network external --provider:network_type flat
    neutron subnet-create ext-net $EXTERNAL_NETWORK_CIDR --name ext-subnet --allocation-pool start=$FLOATING_IP_START,end=$FLOATING_IP_END --disable-dhcp --gateway $EXTERNAL_NETWORK_GATEWAY
    neutron subnet-update --dns-nameserver $NAMESERVER ext-subnet

    # Get OpenStack demo auth
    source $TOP_DIR/openrc demo demo

    neutron net-create demo-net
    neutron subnet-create demo-net $TENANT_NETWORK_CIDR --name demo-subnet --gateway $TENANT_NETWORK_GATEWAY
    neutron subnet-update --dns-nameserver $NAMESERVER demo-subnet
    neutron router-create demo-router
    neutron router-interface-add demo-router demo-subnet
    neutron router-gateway-set demo-router ext-net

    # Import keys from the current user into the default OpenStack user

    # Add first keypair found in localhost:$HOME/.ssh
    for i in $HOME/.ssh/id_rsa.pub $HOME/.ssh/id_dsa.pub; do
        if [[ -r $i ]]; then
            nova keypair-add --pub_key=$i `hostname`
            break
        fi
    done

    # Add tcp/22 and icmp to default security group
    nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
    nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0

fi
