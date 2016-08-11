#!/bin/bash

# clear out the hop times

nfp-rtsym -l0x0000008000 _hoptime_data:0 0
