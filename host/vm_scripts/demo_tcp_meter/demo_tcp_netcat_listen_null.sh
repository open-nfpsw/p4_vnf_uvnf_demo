#!/bin/bash

NS_V2=ns1

ip netns exec $NS_V2 nc -l 9999 > /dev/null
