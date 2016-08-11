#!/usr/bin/python

# a little python utility for reporting the hop times
# it uses the nfp-rtsym tool to read the hop times
# and it parses the output and report the non-zero values

import subprocess

p = subprocess.Popen(['nfp-rtsym', '-v', '_hoptime_data'],
                     stdout=subprocess.PIPE,
                     stderr=subprocess.PIPE)
out, err = p.communicate()

vals = []
for l in out.split('\n'):
    words = l.split(' ')
    for w in words[1:]:
        try: # a little fruity
            vals.append(int(w, 0))
        except:
            pass

for i in range(len(vals)/8):
    max_val = (vals[i*8 + 0] << 32) + (vals[i*8 + 1] << 0)
    min_val = (vals[i*8 + 2] << 32) + (vals[i*8 + 3] << 0)
    count = (vals[i*8 + 4] << 32) + (vals[i*8 + 5] << 0)
    total_latency = (vals[i*8 + 6] << 32) + (vals[i*8 + 7] << 0)

    if count == 0:
        continue

    ave_val = total_latency / (1.0 * count)

    me_rate = 800.0

    mult = 16/me_rate

    max_val *= mult
    min_val *= mult
    ave_val *= mult

    print "port %x [count %d] : min %f us, max %f us, ave %f us" % (i, count, min_val, max_val, ave_val)
