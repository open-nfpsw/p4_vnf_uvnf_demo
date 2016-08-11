#!/bin/bash

NS_V2_IP=10.1.2.1
NS_V3_IP=10.1.3.1

NS_V2=ns1
NS_V3=ns2

NS_V2_ETH0=veth_ns1_0
NS_V2_ETH1=veth_ns1_1

ip netns exec $NS_V2 ping $* $NS_V3_IP
