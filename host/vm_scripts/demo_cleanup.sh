#!/bin/bash

# shut down all the VMs and remove the namespace stuff

if [ -z "$TEST_PORT" ]; then
    echo "error: TEST_PORT is not defined"
    exit 1
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

if ssh root@$VM0_IP true >& /dev/null ; then
    ssh root@$VM0_IP poweroff
fi

if ssh root@$VM1_IP true >& /dev/null ; then
    ssh root@$VM1_IP poweroff
fi

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
