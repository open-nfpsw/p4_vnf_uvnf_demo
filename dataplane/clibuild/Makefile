#
# Paths
#

ifndef SDKDIR
SDKDIR=/opt/nfp-sdk-6.0-beta2
$(info using default SDKDIR: $(SDKDIR))
endif

OUTDIR = ./out
# output dir for the PIF compile
PIFOUTDIR = $(OUTDIR)/pif

P4BUILD = $(SDKDIR)/p4/bin/nfp4build

#
# Defines
#

PROJECT=p4_vnf_uvnf_demo

ifndef PLATFORM
#PLATFORM=hydrogen
PLATFORM=starfighter1
$(info building for platform: $(PLATFORM))
endif

#
# P4/front-end compiler options
#

# explicitly set the p4 compile version
P4C_OPTS = --nfp4c_p4_version 1.0

#
# IR/back-end compiler options
#

# strict P4 table implementation
# with this enabled you need default rules
# for all tables to have any effect
# even those which have a fixed result
IRC_OPTS = --nfirc_strictp4

#
# Firmware compile options
#

# use 4 context mode for dataplane workers
# this is pretty much always required due to register pressure
FWC_OPTS = -r

#
# Input files
#

P4SRC = ../p4src/p4_vnf_uvnf_demo.p4
CSRC = ../csrc/plugin.c

#
# Output files
#

# bug in nfp4build means we cant set the makefile for now
#MKFILE = $(OUTDIR)/buildfw.mk
NFPFW = $(OUTDIR)/$(PROJECT).nffw

#
# Build targets
#

$(NFPFW): $(P4SRC) $(CSRC)
	$(P4BUILD)  -l $(PLATFORM) \
				$(P4C_OPTS) \
				$(IRC_OPTS) \
				$(FWC_OPTS) \
				-o $(NFPFW) -p $(PIFOUTDIR) \
				-c $(CSRC) -4 $(P4SRC)

clean:
	rm -rf $(OUTDIR) Makefile-nfp4build
