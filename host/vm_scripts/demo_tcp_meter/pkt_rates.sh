#!/bin/bash

# dump the packet rates into at out of the vlan interfaces
# used to show the tcp meter packet rate being applied

if [ -z "$TEST_PORT" ]; then
    echo "error: TEST_PORT is not defined"
    exit 1
fi

PERIOD=2

CNT_3OLD=`ifconfig ${TEST_PORT}.3 | grep "RX packets:" | sed -e 's/RX packets://' | sed -e 's/ error.*//'`
CNT_2OLD=`ifconfig ${TEST_PORT}.2 | grep "RX packets:" | sed -e 's/RX packets://' | sed -e 's/ error.*//'`

sleep $PERIOD

CNT_3=`ifconfig ${TEST_PORT}.3 | grep "RX packets:" | sed -e 's/RX packets://' | sed -e 's/ error.*//'`
CNT_2=`ifconfig ${TEST_PORT}.2 | grep "RX packets:" | sed -e 's/RX packets://' | sed -e 's/ error.*//'`

echo "pkts/s ${TEST_PORT}.2 :  "$[(CNT_2 - CNT_2OLD) / PERIOD]

echo "pkts/s ${TEST_PORT}.3 :  "$[(CNT_3 - CNT_3OLD) / PERIOD]

echo "pkts/s ${TEST_PORT}.2+3 :  "$[(CNT_3 - CNT_3OLD + CNT_2 - CNT_2OLD) / PERIOD]
