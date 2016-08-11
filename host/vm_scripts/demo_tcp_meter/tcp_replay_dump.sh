#!/bin/bash
if [ -z "$TEST_PORT" ]; then
    echo "error: TEST_PORT is not defined"
    exit 1
fi
tcpreplay -l0 -K -i ${TEST_PORT}.2 tcp.pcap >& /dev/null
