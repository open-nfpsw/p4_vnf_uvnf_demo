#!/bin/bash
# Copyright (C) 2015-2016 Netronome Systems, Inc.  All rights reserved.

set -e

# ENV VARS
#
# LOAD_NETDEV - load the netdev driver
# NUM_VFS - number of VFs to create
# BASE_MAC - base MAC address for netdevs, #VF masked into lower word
# NBI_MAC8_JSON - MAC config for NBI 0
# NBI_MAC9_JSON - MAC config for NBI 1
# NBI_TM_JSON - TM config for NBI 0 and 1
# NFPSHUTILS - Location of nfp-shutils
# DISABLE_NFD - Set to "yes" to disable
# DETECT_MAC - Set to "yes" to detect the NFP MAC config and set links to platform_*.json files for NBI init

on_err () {
	echo "Error on line $1: err($2)"
	exit 1
}

trap 'on_err $LINENO $?' ERR

#
# Variables
#

# Loaded from command line
firmwarefile=

# Loaded from enrivonment
LOAD_NETDEV=${LOAD_NETDEV:-}
NUM_VFS=${NUM_VFS:-1}
BASE_MAC=${BASE_MAC:-"00:15:4d:00:00:"}
NETRODIR=${NETRODIR:-/opt/netronome}
NFPPIFDIR=${NFPPIFDIR:-/opt/nfp_pif}
NFPSHUTILS=${NFPSHUTILS:-$NETRODIR/bin/nfp-shutils}
DISABLE_NFD=${DISABLE_NFD:-no}
DETECT_MAC=${DETECT_MAC:-yes}

# look for starfighter (19ee:6000) else look for hydrogen card (19ee:4000)
if lspci -d 19ee:6000 | grep Netronome > /dev/null 2>&1
then
    PCI_ID=`setpci -v -d 19ee:6000 ECAP_DSN+5.B  | grep "= 10" | \
        cut -f 1 -d " " | sed -e "s/^0000://" -e "s/:00.0$//"`
elif lspci -d 19ee:4000 | grep Netronome > /dev/null 2>&1
then
    PCI_ID=`setpci -v -d 19ee:4000 ECAP_DSN+5.B  | grep "= 10" | \
         cut -f 1 -d " " | sed -e "s/^0000://" -e "s/:00.0$//"`
else
    echo "Can't find the NFP on the PCI bus"
fi
PF_SYS="/sys/bus/pci/devices/0000:${PCI_ID}:00.0"

# Check for ARI support
ARI_SUPPORT=$($NETRODIR/bin/nfp-support | grep ARI -m1)

if [[ "$ARI_SUPPORT" == *"PASS"* ]]; then
  ARI=1
  echo "ARI Support detected"
else
  ARI=0
  echo "No ARI Support found. VFs not supported."
fi


#
# Functions
#
set_platform_vars() {
  PLATFORM=`$NETRODIR/bin/nfp-hwinfo | grep assembly.model | sed 's/.*=//g'`
  VARIANT=`$NETRODIR/bin/nfp-mactool -p 0x1  2>&1 >/dev/null | sed -e 's/^.* \([^ ]*GE\).*/\1/'`

  PHY0_ETH_COUNT=`$NETRODIR/bin/nfp-phymod -i 0 2>&1 | grep eth | wc -l`
  PHY1_ETH_COUNT=`$NETRODIR/bin/nfp-phymod -i 1 2>&1 | grep eth | wc -l`

  # default configs
  MAC8_CFG=hy-1x40GE-prepend.json
  DMA8_CFG=nfp_nbi8_dma_hy.json

  if [[ "$PLATFORM" == *"starfighter1"* ]] ; then
    DMA8_CFG=nfp_nbi8_dma_sf.json
    if [ "$PHY0_ETH_COUNT" -eq "1" -a "$PHY1_ETH_COUNT" -eq "0" ]; then
        MAC8_CFG=sf1-1x100GE-prepend.json
    elif [ "$PHY0_ETH_COUNT" -eq "10" -a "$PHY1_ETH_COUNT" -eq "0" ]; then
        MAC8_CFG=sf1-10x10GE-prepend.json
    elif [ "$PHY0_ETH_COUNT" -eq "2" -a "$PHY1_ETH_COUNT" -eq "0" ]; then
        MAC8_CFG=sf1-2x40GE-prepend.json
    elif [ "$PHY0_ETH_COUNT" -eq "1" -a "$PHY1_ETH_COUNT" -eq "1" ]; then
        MAC8_CFG=sf1-2x40GE-prepend.json
    elif [ "$PHY0_ETH_COUNT" -eq "4" -a "$PHY1_ETH_COUNT" -eq "4" ]; then
        MAC8_CFG=sf1-8x10GE-prepend.json
    elif [ "$PHY0_ETH_COUNT" -eq "4" -a "$PHY1_ETH_COUNT" -eq "1" ]; then
        MAC8_CFG=sf1-4x10GE-1x40GE-prepend.json
    else
        echo "Unrecognised starfighter variant $VARIANT"
        exit 1
    fi
  elif [ "$PLATFORM" = "hydrogen" ] ; then
    DMA8_CFG=nfp_nbi8_dma_hy.json
    if [ "$PHY0_ETH_COUNT" -eq "1" -a "$PHY1_ETH_COUNT" -eq "0" ]; then
        MAC8_CFG=hy-1x40GE-prepend.json
    elif [ "$PHY0_ETH_COUNT" -eq "4" -a "$PHY1_ETH_COUNT" -eq "0" ]; then
        MAC8_CFG=hy-4x10GE-prepend.json
    else
        echo "Unrecognised hydrogen variant $VARIANT"
        exit 1
    fi
  elif [ "$PLATFORM" = "lithium" ] ; then
    #DMA8_CFG=nfp_nbi8_dma_li.json
    if [ "$PHY0_ETH_COUNT" -eq "1" -a "$PHY1_ETH_COUNT" -eq "1" ]; then
        MAC8_CFG=li-2x10GE-prepend.json
    else
        echo "Unrecognised lithium variant $VARIANT"
        exit 1
    fi
  elif [ "$PLATFORM" = "beryllium" ] ; then
    #DMA8_CFG=nfp_nbi8_dma_be.json
    if [ "$PHY0_ETH_COUNT" -eq "1" -a "$PHY1_ETH_COUNT" -eq "0" ]; then
        MAC8_CFG=be-1x40GE-prepend.json
    elif [ "$PHY0_ETH_COUNT" -eq "4" -a "$PHY1_ETH_COUNT" -eq "0" ]; then
        MAC8_CFG=be-4x10GE-prepend.json
    elif [ "$PHY0_ETH_COUNT" -eq "1" -a "$PHY1_ETH_COUNT" -eq "1" ]; then
        MAC8_CFG=be-2x40GE-prepend.json
    elif [ "$PHY0_ETH_COUNT" -eq "4" -a "$PHY1_ETH_COUNT" -eq "1" ]; then
        MAC8_CFG=be-4x10GE-1x40GE-prepend.json
    elif [ "$PHY0_ETH_COUNT" -eq "4" -a "$PHY1_ETH_COUNT" -eq "4" ]; then
        MAC8_CFG=be-8x10GE-prepend.json
    else
        echo "Unrecognised beryllium variant $VARIANT"
        exit 1
    fi
  else
    echo "Unrecognised platform $PLATFORM"
    exit 1
  fi

  # Setup links
  ln -sf "$NFPPIFDIR/etc/configs/$MAC8_CFG" "$NFPPIFDIR/etc/configs/platform_mac8_config.json"
  ln -sf "$NFPPIFDIR/etc/configs/$DMA8_CFG" "$NFPPIFDIR/etc/configs/platform_dma8_config.json"
  echo "Detected $PLATFORM platform, using $MAC8_CFG for MAC init"
  echo " and $DMA8_CFG for DMA init (when not in debug mode)"
}


nfd_post_load() {
    echo -n " - Emumerating $NUM_VFS VFs..."
    echo $NUM_VFS > ${PF_SYS}/sriov_numvfs
    sleep 0.5
    echo "done"
}

nfd_pre_unload() {
    echo "Preparing for NFD unload:"

    echo -n " - Removing VFs..."
    echo 0 > ${PF_SYS}/sriov_numvfs
    sleep 0.5
    echo "done"

    echo -n " - Remove net_dev"
    (rmmod nfp_netvf || true) 2>/dev/null
    (rmmod igb_uio || true) 2>/dev/null
    (rmmod nfp_net || true) 2>/dev/null
    sleep 1
    echo "done"
}

#
# Interface functions
#

load() {
    if [ "$DETECT_MAC" = "yes" ]; then
        set_platform_vars
    fi
    
    (. $NFPSHUTILS; appctl start $firmwarefile)

    if [ "$DISABLE_NFD" = "no" ] && [ $ARI -eq 1 ]; then
        nfd_post_load
    fi

    # enable all pif application MEs
    # TODO: this may change

    MELIST=`$NETRODIR/bin/nfp-rtsym -L |grep _parrep_0 | sed -e 's/\._parrep_0.*//'`
    echo "Detected PIF worker MES:"
    echo "$MELIST"

    for me in $MELIST; do
        $NETRODIR/bin/nfp-reg mecsr:$me.Mailbox0=1
    done

    # enable mac interfaces
    $NETRODIR/bin/nfp-mactool -u -p 0xfff
}

unload() {
    if [ "$DISABLE_NFD" = "no" ] && [ $ARI -eq 1 ]; then
        nfd_pre_unload
    fi

    echo "Claiming mac.stat resource"
    $NETRODIR/bin/nfp-res --claim mac.stat
    echo -n "Firmware unload, NFP Reset..."
    RET=0
    if ! (bash -c ". $NFPSHUTILS; appctl stop") ; then
        >&2 echo "Failed to unload NFP"
        RET=1
    fi
    echo "Unclaiming mac.stat resource"
    $NETRODIR/bin/nfp-res --unclaim mac.stat
    exit $RET
}

usage() {
    echo $"Usage:"
    echo -e "\t $0 {load|unload} <OPERATION ARGUMENTS> "
    echo -e "\t OPERATION ARGUMENTS:"
    echo -e "\t \t load [-f|--firmwarefile <fwfile>]"
    echo -e "\t \t unload"
    echo $"When envoking load option a firmwarefile file needs to be specified"
}

while [ -n "$1" ]; do
    key="$1"
    
    case $key in
        load)
        OPERATION="load"
        ;;
        unload)
        OPERATION="unload"
        ;;
        -f|--firmwarefile)
        firmwarefile="$2"
        shift # past argument
        ;;
        *)
                # unknown option
        ;;
    esac
    shift # past argument or value
done

case $OPERATION in
  load)
      if !( [ -f "$firmwarefile" ] ); then
          echo "Firmware file not specified"
          usage
          exit 2
      fi
      load
      ;;
  unload)
      unload
      ;;
   *)
      usage
      exit 2
esac


