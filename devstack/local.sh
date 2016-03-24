#!/usr/bin/env bash
set -x

# Put the main IP between 240 -  250 and this will set a range between 200-210
BASEIP=172.27.162.
NAMESERVER=172.27.1.251
EXTERNAL_NETWORK_CIDR=172.27.162.0/24
EXTERNAL_NETWORK_GATEWAY=172.27.162.254
TENANT_NETWORK_CIDR=192.168.1.0/24
TENANT_NETWORK_GATEWAY=192.168.1.254

#MYID=$(hostname -s | cut -d '-' -f 2)
#MYIP=$BASEIP$(expr $MYID + 100)
MYIP=$(ip -o -f inet a | awk '/'${BASEIP}'/{split($4,pa,".");split(pa[4],addr,"/");print addr[1]}')
START=$(expr \( \( $MYIP - 240 \) \* 10 \) + 100 )
END=$(expr $START + 9)
FLOATING_IP_START=$BASEIP$START
FLOATING_IP_END=$BASEIP$END

function get_field {
    while read data; do
        if [ "$1" -lt 0 ]; then
            field="(\$(NF$1))"
        else
            field="\$$(($1 + 1))"
        fi
        echo "$data" | awk -F'[ \t]*\\|[ \t]*' "{print $field}"
    done
}

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
#sudo ovs-vsctl add-port br-ex $PUBLIC_PORT
#sudo ip link set dev $PUBLIC_PORT up

unset OS_USER_DOMAIN_ID
unset OS_PROJECT_DOMAIN_ID

if is_service_enabled nova; then

    # Get OpenStack admin auth
    source $TOP_DIR/openrc admin admin

    neutron net-create ext-net --router:external=True --provider:physical_network=public --provider:network_type=flat
    neutron subnet-create ext-net $EXTERNAL_NETWORK_CIDR --name ext-subnet --allocation-pool start=$FLOATING_IP_START,end=$FLOATING_IP_END --disable-dhcp --gateway $EXTERNAL_NETWORK_GATEWAY
    neutron subnet-update --dns-nameserver $NAMESERVER ext-subnet

    cinder type-create solidfire
    cinder type-key solidfire set volume_backend_name=solidfire

    # set VOLUME_BACKEND_NAME to the name of your array
    VOLUME_BACKEND_NAME="solidfire"

    # Setup 4 arrays corresponding to your Volume types and QoS settings
    VOL_TYPES=( "silver" "bronze" "gold" "webserver" "platinum" )
    DESCRIPTION=( '$[$1.12/GB/month]' '$[0.50/GB/month]' '[$2.10/GB/month]' '[$0.35/GB/month]' '[$3.00/GB/month]' )
    MIN=(        500    100      1000   100       2000    )
    MAX=(        800    200      1500  1000       2400    )
    BURST=(      900    250      1700  1500       2500    )

    INDEX=0
    for VOL_TYPE in "${VOL_TYPES[@]}"
    do
       echo "Create Volume Type: ${VOL_TYPE}"
       TYPE_DESC="IOPS=${MIN[${INDEX}]}/${MAX[${INDEX}]}/${BURST[${INDEX}]} ${DESCRIPTION[${INDEX}]}"
       TYPENAME_TYPEID=$(cinder type-create --description "${TYPE_DESC}" ${VOL_TYPE} | grep ${VOL_TYPE} | get_field 1)
       echo "Creating QoS Specs"
       QOS_ID=$(cinder qos-create ${VOL_TYPE}-qos qos:minIOPS=${MIN[${INDEX}]} qos:maxIOPS=${MAX[${INDEX}]} qos:burstIOPS=${BURST[${INDEX}]} | grep id | get_field 2)
       echo "Setting volume backend name ..."
       cinder type-key ${TYPENAME_TYPEID} set volume_backend_name=${VOLUME_BACKEND_NAME}
       echo "Associating QoS specs with volume type .... "
       cinder qos-associate ${QOS_ID} ${TYPENAME_TYPEID}
       ((INDEX++))
    done


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
