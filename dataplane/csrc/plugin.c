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
 * C Sandbox source code for P4 SmartNIC demo:
 * P4-based VNF and Micro-VNF chaining for servers with SmartNICs
 *
 * Code contains two function called from P4 custom primitive actions:
 * pif_plugin_payload_scan() :
 *      a simple single token payload scanner
 *
 * pif_plugin_hoptime_statistics() :
 *      VNF hop time measurement and statistics
 *
 * Note that this code uses C dialect called microC for NFPs
 * A essential reference for this can be found at:
 * http://open-nfp.org/media/pdfs/the-joy-of-micro-c.pdf
 *
 */

#include <stdint.h>
#include <nfp/me.h>
#include <nfp/mem_atomic.h>
#include <pif_common.h>
#include "pif_plugin.h"

/*
 * Payload scan: search the payload for a string
 */

/* we define a static search string */
static __lmem uint8_t needle[] = {'b', 'o', 'o', 'm'};

/* an exported variable counting number of detections
 * __export means will be able to access this memory from the host
 */
volatile __export __mem uint32_t needle_detections = 0;

/* Payload chunk size in LW (32-bit) and bytes */
#define CHUNK_LW 8
#define CHUNK_B ((CHUNK_LW)*4)

volatile __export __mem uint32_t pif_mu_len = 0;

int pif_plugin_payload_scan(EXTRACTED_HEADERS_T *headers,
                            MATCH_DATA_T *match_data)
{
    __mem uint8_t *payload;
    __xread uint32_t pl_data[CHUNK_LW];
    __lmem uint32_t pl_mem[CHUNK_LW];
    int needle_progress = 0;
    int i, count, to_read;
    uint32_t mu_len, ctm_len;

    /* figure out how much data is in external memory vs ctm */

    if (pif_pkt_info_global.split) { /* payload split to MU */
        uint32_t sop; /* start of packet offset */
        sop = PIF_PKT_SOP(pif_pkt_info_global.pkt_buf, pif_pkt_info_global.pkt_num);
        mu_len = pif_pkt_info_global.pkt_len - (256 << pif_pkt_info_global.ctm_size) + sop;
    } else /* no data in MU */
        mu_len = 0;

    /* debug info for mu_split */
    pif_mu_len = mu_len;

    /* get the ctm byte count:
     * packet length - offset to parsed headers - byte_count_in_mu
     * Note: the parsed headers are always in ctm
     */
    count = pif_pkt_info_global.pkt_len - pif_pkt_info_global.pkt_pl_off - mu_len;
    /* Get a pointer to the ctm portion */
    payload = pif_pkt_info_global.pkt_buf;
    /* point to just beyond the parsed headers */
    payload += pif_pkt_info_global.pkt_pl_off;

    while (count) {
        /* grab a maximum of chunk */
        to_read = count > CHUNK_B ? CHUNK_B : count;

        /* grab a chunk of memory into transfer registers */
        mem_read8(&pl_data, payload, to_read);

        /* copy from transfer registers into local memory
         * we can iterate over local memory, where transfer
         * registers we cant
         */
        for (i = 0; i < CHUNK_LW; i++)
            pl_mem[i] = pl_data[i];

        /* iterate over all the bytes and do the search */
        for (i = 0; i < to_read; i++) {
            uint8_t val = pl_mem[i/4] >> (8 * (3 - (i % 4)));

            if (val == needle[needle_progress])
                needle_progress += 1;
            else
                needle_progress = 0;

            if (needle_progress >= sizeof(needle)) {
                mem_incr32((__mem uint32_t *)&needle_detections);

                /* drop if found */
                return PIF_PLUGIN_RETURN_DROP;
            }
        }

        payload += to_read;
        count -= to_read;
    }

    /* same as above, but for mu. Code duplicated as a manual unroll */
    if (mu_len) {
        payload = (__addr40 void *)((uint64_t)pif_pkt_info_global.muptr << 11);
        /* skip over the ctm part */
        payload += 256 << pif_pkt_info_global.ctm_size;

        count = mu_len;
        while (count) {
            /* grab a maximum of chunk */
            to_read = count > CHUNK_B ? CHUNK_B : count;

            /* grab a chunk of memory into transfer registers */
            mem_read8(&pl_data, payload, to_read);

            /* copy from transfer registers into local memory
             * we can iterate over local memory, where transfer
             * registers we cant
             */
            for (i = 0; i < CHUNK_LW; i++)
                pl_mem[i] = pl_data[i];

            /* iterate over all the bytes and do the search */
            for (i = 0; i < to_read; i++) {
                uint8_t val = pl_mem[i/4] >> (8 * (3 - (i % 4)));

                if (val == needle[needle_progress])
                    needle_progress += 1;
                else
                    needle_progress = 0;

                if (needle_progress >= sizeof(needle)) {
                    mem_incr32((__mem uint32_t *)&needle_detections);

                    /* drop if found */
                    return PIF_PLUGIN_RETURN_DROP;
                }
            }

            payload += to_read;
            count -= to_read;
        }
    }

    return PIF_PLUGIN_RETURN_FORWARD;
}

/*
 * Hop time operation
 */

/* ingress_port is a 10-bit value */
#define PORTMAX 1024

/* data structure for latency data per port */
struct hoptime_data {
    uint64_t max_latency;
    uint64_t min_latency;
    uint64_t count;
    uint64_t total_latency;
};

/* declare latency data with one extra slot for bad port#
 * this memory is exported so we can get to it from the host
 */
__export __mem struct hoptime_data hoptime_data[PORTMAX + 1];

int pif_plugin_hoptime_statistics(EXTRACTED_HEADERS_T *headers,
                                  MATCH_DATA_T *match_data)
{
    PIF_PLUGIN_hoptime_T *hoptime = pif_plugin_hdr_get_hoptime(headers);
    __xread struct hoptime_data in_xfer;
    __gpr struct hoptime_data out_reg;
    __xwrite struct hoptime_data out_xfer;
    uint64_t ctime, ptime;
    uint64_t latency;
    unsigned port;

    /* Get the time at parsing from the intrinsic metadata timestamp
     * Note that we do this in two parts __0 being the 32 lsbs and __1 the 16
     * msbs
     */
    ctime = pif_plugin_meta_get__intrinsic_metadata__ingress_global_tstamp__0(headers);
    ctime |= ((uint64_t)pif_plugin_meta_get__intrinsic_metadata__ingress_global_tstamp__1(headers)) << 32;

    /* Retrieve ingress port from P4 metadata */
    port = pif_plugin_meta_get__standard_metadata__ingress_port(headers);

    /* we don't error out here, we just use use a reserved bucket */
    if (port >= PORTMAX)
        port = PORTMAX;

    /* Retrieve the previous hop time from the hoptime header field */
    ptime = ((uint64_t)PIF_HEADER_GET_hoptime___time___1(hoptime)) << 32;
    ptime |= PIF_HEADER_GET_hoptime___time___0(hoptime);

    latency = ctime - ptime;

    mem_read32(&in_xfer, &hoptime_data[port], sizeof(in_xfer));

    out_reg = in_xfer;

    if (latency > out_reg.max_latency)
        out_reg.max_latency = latency;

    if (latency < out_reg.min_latency || out_reg.min_latency == 0)
        out_reg.min_latency = latency;

    out_reg.count += 1;
    out_reg.total_latency += latency;

    out_xfer = out_reg;
    mem_write32(&out_xfer, &hoptime_data[port], sizeof(out_xfer));

    return PIF_PLUGIN_RETURN_FORWARD;
}
