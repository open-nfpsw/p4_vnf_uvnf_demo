#!/bin/bash

NS_V2_IP=10.1.2.1
NS_V3_IP=10.1.3.1

NS_V2=ns1
NS_V3=ns2

# create a script here due to quirks piping around ip netns
echo -e "#!/bin/bash\ncat /dev/zero | nc $NS_V2_IP 9999" > tmp.sh
chmod +x tmp.sh
ip netns exec $NS_V3 ./tmp.sh
