#!/bin/bash

#
# do all the setup for the demo
# this includes tearing down and starting VMs
# and setting up all the namespace stuff
# Note that there is an optional argument
# which is mask for which VMs will use DPDK
# the DPDK app is *not* started from here
#

#
# a little error trap
#

on_err () {
        echo "Error on line $1: err($2)"
        exit 1
}

trap 'on_err $LINENO $?' ERR

#
# setup parms
#

if [ -z "$TEST_PORT" ]; then
    echo "error: TEST_PORT is not defined"
    exit 1
fi

if [ -z "$1" ]; then
    DPDK_MASK=0
else
    DPDK_MASK=$1
fi

VM0_IP=${VM0_IP:-192.168.122.200}
VM1_IP=${VM1_IP:-192.168.122.201}

VM0_NAME=vnf_demo_0
VM1_NAME=vnf_demo_1

NS_V2_MAC=00:15:4d:00:00:0a
NS_V3_MAC=00:15:4d:00:00:0b
NS_V2_IP=10.1.2.1
NS_V3_IP=10.1.3.1

NS_V2=ns1
NS_V3=ns2

NS_V2_BR=ns1
NS_V3_BR=ns2

NS_V2_ETH0=veth_ns1_0
NS_V2_ETH1=veth_ns1_1

NS_V3_ETH0=veth_ns2_0
NS_V3_ETH1=veth_ns2_1

modprobe vfio-pci

#
# tear down old config
#

echo checking if vms are up

WAIT=0.5

# shutdown VMs if up
if ssh root@$VM0_IP true >& /dev/null ; then
    ssh root@$VM0_IP poweroff
    WAIT=3
    echo shutting down vm0
fi

if ssh root@$VM1_IP true >& /dev/null ; then
    ssh root@$VM1_IP poweroff
    WAIT=3
    echo shutting down vm1
fi

sleep $WAIT

(vconfig rem ${TEST_PORT}.2 || true) 2> /dev/null
(vconfig rem ${TEST_PORT}.3 || true) 2> /dev/null
(ifconfig br_v0_1 down || true) 2> /dev/null
(ifconfig br_v2_3 down || true) 2> /dev/null
(brctl delbr br_v0_1 || true) 2> /dev/null
(brctl delbr br_v2_3 || true) 2> /dev/null
(ifconfig $NS_V2_BR down || true) 2> /dev/null
(ifconfig $NS_V3_BR down || true) 2> /dev/null
(brctl delbr $NS_V2_BR || true) 2>/dev/null
(brctl delbr $NS_V3_BR || true) 2>/dev/null
(ip netns del $NS_V2 || true) 2>/dev/null
(ip netns del $NS_V3 || true) 2>/dev/null
(ip link del $NS_V2_ETH0 || true) 2>/dev/null
(ip link del $NS_V2_ETH1 || true) 2>/dev/null
(ip link del $NS_V3_ETH0 || true) 2>/dev/null
(ip link del $NS_V3_ETH1 || true) 2>/dev/null

# from here errors are fatal
set -e

#
# Bring up VMs
#

# start them again
virsh start $VM0_NAME
virsh start $VM1_NAME

echo waiting for VMs to come up
TIMEOUT=10

VMUP=0
while [ $TIMEOUT -gt 0 ]; do 
    if ssh root@$VM0_IP true >& /dev/null ; then
        VMUP=$[VMUP | 1]
    fi
    if ssh root@$VM1_IP true >& /dev/null ; then
        VMUP=$[VMUP | 2]
    fi
    if [ $VMUP -eq 3 ]; then
        break
    fi
    sleep 0.5
    TIMEOUT=$[ TIMEOUT - 1 ]
done
if [ $TIMEOUT -eq 0 ]; then
    echo VMs didnt come up
    exit 1
fi
echo done

VM0_DPDK=$[DPDK_MASK & 0x1]
VM1_DPDK=$[DPDK_MASK & 0x2]

if [ $VM0_DPDK -eq 0 ]; then
    ssh root@$VM0_IP /root/start-linuxbr.sh
    ssh root@$VM0_IP ethtool -K eth1 rxvlan off txvlan off
    ssh root@$VM0_IP ethtool -K eth2 rxvlan off txvlan off
fi

if [ $VM1_DPDK -eq 0 ]; then
    ssh root@$VM1_IP /root/start-linuxbr.sh
    ssh root@$VM1_IP ethtool -K eth1 rxvlan off txvlan off
    ssh root@$VM1_IP ethtool -K eth2 rxvlan off txvlan off
fi

#
# Set up the test port + vlans + name spaces
#

sysctl -w net.ipv6.conf.${TEST_PORT}.disable_ipv6=1
ifconfig ${TEST_PORT} up

ethtool -K ${TEST_PORT} rxvlan off
ethtool -K ${TEST_PORT} txvlan off

vconfig add ${TEST_PORT} 2
vconfig add ${TEST_PORT} 3
sysctl -w net/ipv6/conf/${TEST_PORT}.2/disable_ipv6=1
sysctl -w net/ipv6/conf/${TEST_PORT}.3/disable_ipv6=1

ifconfig ${TEST_PORT}.2 up
ifconfig ${TEST_PORT}.3 up

ip netns add $NS_V2
ip link add $NS_V2_ETH0 type veth peer name $NS_V2_ETH1
ip link set $NS_V2_ETH1 netns $NS_V2
ip netns exec $NS_V2 ifconfig $NS_V2_ETH1 $NS_V2_IP netmask 255.0.0.0
ip netns exec $NS_V2 ifconfig $NS_V2_ETH1 hw ether $NS_V2_MAC
ip netns exec $NS_V2 ifconfig $NS_V2_ETH1 mtu 1500

ip netns add $NS_V3
ip link add $NS_V3_ETH0 type veth peer name $NS_V3_ETH1
ip link set $NS_V3_ETH1 netns $NS_V3
ip netns exec $NS_V3 ifconfig $NS_V3_ETH1 $NS_V3_IP netmask 255.0.0.0
ip netns exec $NS_V3 ifconfig $NS_V3_ETH1 hw ether $NS_V3_MAC
ip netns exec $NS_V3 ifconfig $NS_V3_ETH1 mtu 1500

ip netns exec $NS_V2 arp -s $NS_V3_IP $NS_V3_MAC
ip netns exec $NS_V3 arp -s $NS_V2_IP $NS_V2_MAC

brctl addbr $NS_V2_BR
brctl addif $NS_V2_BR ${TEST_PORT}.2 $NS_V2_ETH0
ifconfig $NS_V2_BR up
ifconfig $NS_V2_ETH0 up

brctl addbr $NS_V3_BR
brctl addif $NS_V3_BR ${TEST_PORT}.3 $NS_V3_ETH0
ifconfig $NS_V3_BR up
ifconfig $NS_V3_ETH0 up
