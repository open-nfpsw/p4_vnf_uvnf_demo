#!/bin/bash

# manually start the RTE configured to not load any VFIO modules/devices
# we will set up the VFIO bits manually

RTE_DIR=/opt/nfp_pif

CTL_SCRIPT=./pif_ctl_no_modules.sh

export LD_LIBRARY_PATH=$RTE_DIR/lib:/opt/netronome/lib
export NUM_VFS=4
export NBI_DMA8_JSON=$RTE_DIR/etc/configs/platform_dma8_config.json
export NBI_MAC8_JSON=$RTE_DIR/etc/configs/platform_mac8_config.json
export NBI_TM_JSON=nfp_nbi_tm_12x10GE.json
export NFPSHUTILS=$RTE_DIR/scripts/shared/nfp-shutils
export DISABLE_NFD=no
export DETECT_MAC=yes

/opt/nfp_pif/bin/pif_rte -z -s $CTL_SCRIPT --log_file /tmp/nfp-sdk6-rte.log
