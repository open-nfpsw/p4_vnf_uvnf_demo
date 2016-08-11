#!/bin/bash

NS_V2_IP=10.1.2.1
NS_V3_IP=10.1.3.1

NS_V2=ns1
NS_V3=ns2

ip netns exec $NS_V2 nc -u -l $NS_V2_IP 9999
