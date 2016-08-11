#!/bin/bash

#
# Copyright (C) 2016, Netronome Systems, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#     Unless required by applicable law or agreed to in writing, software
#     distributed under the License is distributed on an "AS IS" BASIS,
#     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#     See the License for the specific language governing permissions and
#     limitations under the License.
#
#

set -e

SDKDIR=/opt/nfp-sdk-6.0-beta2

if [ -n "$SERVER" ] ; then
    SERVER="-r $SERVER"
fi

# load the design
$SDKDIR/p4/bin/rtecli $SERVER design-load -f out/p4_vnf_uvnf_demo.nffw -p out/pif/pif_design.json

# load the rules
$SDKDIR/p4/bin/rtecli $SERVER config-reload -c ../user_config/p4_vnf_uvnf_demo_p0.p4cfg
