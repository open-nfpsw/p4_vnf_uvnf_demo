/*
 * Copyright (C) 2016, Netronome Systems, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *     Unless required by applicable law or agreed to in writing, software
 *     distributed under the License is distributed on an "AS IS" BASIS,
 *     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *     See the License for the specific language governing permissions and
 *     limitations under the License.
 *
 */

/*
 * P4 source for the demo:
 * P4-based VNF and Micro-VNF chaining for servers with SmartNICs
 *
 * This P4 project will direct packets to VFs based on VLAN ID
 * It will optionally insert a custom hoptime header container
 * a timestamp on egress and remove it on ingress. Upon removal
 * the delta in timestamp is accounted for in a C sandbox function.
 *
 * There is also a payload scanner which may drop the traffic.
 * Finally it includes metering for all TCP traffic
 */

#define ETHERTYPE_VLAN 0x8100
#define ETHERTYPE_IPV4 0x0800
#define ETHERTYPE_HOPTIME 0x9999
#define IPPROTO_TCP 6

/*
 * Header declarations
 */

header_type ethernet_t {
    fields {
        dstAddr : 48;
        srcAddr : 48;
        etherType : 16;
    }
}

header_type vlan_t {
    fields {
        pcp : 3;
        cfi : 1;
        vid : 12;
        etherType : 16;
    }
}

header_type hoptime_t {
    fields {
        time : 48;
        etherType : 16;
    }
}

header_type ipv4_t {
    fields {
        version : 4;
        ihl : 4;
        diffserv : 8;
        totalLen : 16;
        identification : 16;
        flags : 3;
        fragOffset : 13;
        ttl : 8;
        protocol : 8;
        hdrChecksum : 16;
        srcAddr : 32;
        dstAddr: 32;
    }
}


header_type tcp_t {
    fields {
        srcPort : 16;
        dstPort : 16;
        seqNo : 32;
        ackNo : 32;
        dataOffset : 4;
        res : 4;
        flags : 8;
        window : 16;
        checksum : 16;
        urgentPtr : 16;
    }
}

// declare the special timestamp metadata
// this will automatically get populated with a timestamp
// immediately before parsing
header_type intrinsic_metadata_t {
    fields {
        ingress_global_tstamp : 48;
    }
}

header_type meta_t {
    fields {
        tcp_meter_colour : 2;
    }
}

primitive_action payload_scan();
primitive_action hoptime_statistics();

header ethernet_t ethernet;
header vlan_t vlan;
header hoptime_t hoptime;
header ipv4_t ipv4;
header tcp_t tcp;

metadata meta_t meta;
metadata intrinsic_metadata_t intrinsic_metadata;

/*
 * Parser
 */

parser start {
    set_metadata(meta.tcp_meter_colour, 0); /* precolour green */
    return parse_ethernet;
}

parser parse_ethernet {
    extract(ethernet);
    return select(latest.etherType) {
        ETHERTYPE_VLAN : parse_vlan;
        ETHERTYPE_IPV4 : parse_ipv4;
        ETHERTYPE_HOPTIME : parse_hoptime;
        default: ingress;
    }
}

parser parse_vlan {
    extract(vlan);
    return select(latest.etherType) {
        ETHERTYPE_IPV4 : parse_ipv4;
        ETHERTYPE_HOPTIME : parse_hoptime;
        default: ingress;
    }
}

parser parse_hoptime {
    extract(hoptime);
    return select(latest.etherType) {
        ETHERTYPE_IPV4 : parse_ipv4;
        default: ingress;
    }
}

parser parse_ipv4 {
    extract(ipv4);
    return select(latest.protocol) {
        IPPROTO_TCP : parse_tcp;
        default: ingress;
    }
}

parser parse_tcp {
    extract(tcp);
    return ingress;
}

/*
 * Ingress
 */

/* attach a pragma that will automatically drop the packet
 * when the meter returns red
 */
@pragma netro meter_drop_red
meter tcp_meter {
    type: packets;
    result: meta.tcp_meter_colour;
    instance_count: 1;
}

action do_tcp_throttle(espec) {
    /* special tcp path, throttle and forward */
    execute_meter(tcp_meter, 0, meta.tcp_meter_colour);
    modify_field(standard_metadata.egress_spec, espec);
}

table tcp_throttle {
    actions {
		do_tcp_throttle;
    }
}

action do_forward(espec) {
    modify_field(standard_metadata.egress_spec, espec);
    payload_scan();
}

table forward {
    reads {
        standard_metadata.ingress_port : exact;
    }
    actions {
		do_forward;
    }
}

action do_forward_vlan(espec) {
    modify_field(standard_metadata.egress_spec, espec);
    payload_scan();
}

table forward_vlan {
    reads {
        standard_metadata.ingress_port : exact;
        vlan.vid: exact;
    }
    actions {
		do_forward_vlan;
    }
}

action do_process_hoptime_eth() {
    hoptime_statistics();
    modify_field(ethernet.etherType, hoptime.etherType);
    remove_header(hoptime);
}

action do_process_hoptime_vlan() {
    hoptime_statistics();
    modify_field(vlan.etherType, hoptime.etherType);
    remove_header(hoptime);
}

table process_hoptime_vlan {
    actions {
		do_process_hoptime_vlan;
    }
}

table process_hoptime_eth {
    actions {
		do_process_hoptime_eth;
    }
}

control ingress {
    if (valid(hoptime)) {
        if (valid(vlan)) {
            apply(process_hoptime_vlan);
        } else {
            apply(process_hoptime_eth);
        }
    }

    if (valid(tcp)) {
        apply(tcp_throttle);
    } else {
        if (valid(vlan)) {
            apply(forward_vlan);
        } else {
            apply(forward);
        }
    }
}

/*
 * Egress
 */

action translate_vlan(new_vid) {
    modify_field(vlan.vid, new_vid);
}

table manipulate_vlan {
    reads {
        vlan.vid: exact;
        standard_metadata.egress_port: exact;
    }
    actions {
		translate_vlan;
    }
}

action do_insert_hoptime_eth() {
    add_header(hoptime);
    modify_field(hoptime.etherType, ethernet.etherType);
    modify_field(ethernet.etherType, ETHERTYPE_HOPTIME);
    modify_field(hoptime.time, intrinsic_metadata.ingress_global_tstamp);
}

action do_insert_hoptime_vlan() {
    add_header(hoptime);
    modify_field(hoptime.etherType, vlan.etherType);
    modify_field(vlan.etherType, ETHERTYPE_HOPTIME);
    modify_field(hoptime.time, intrinsic_metadata.ingress_global_tstamp);
}

table insert_hoptime_vlan {
    reads {
        standard_metadata.egress_port: exact;
    }
    actions {
		do_insert_hoptime_vlan;
    }
}

table insert_hoptime_eth {
    reads {
        standard_metadata.egress_port: exact;
    }
    actions {
		do_insert_hoptime_eth;
    }
}

control egress {
    if (valid(vlan)) {
		apply(manipulate_vlan);
        apply(insert_hoptime_vlan);
    } else {
        apply(insert_hoptime_eth);
    }
}
