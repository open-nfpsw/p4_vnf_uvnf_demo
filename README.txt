Files for "P4-based VNF and Micro-VNF chaining for servers with SmartNICs"
--------------------------------------------------------------------------

This package include source for the demo given at the 2016 P4 Conference
and the 3rd Open NFP webinar hosted in August 2016.

The demo does the following:
* routes traffic between two Linux network namespaces via two chain VNFs
    - The VNFs are implemented as L2 bridges
    - VLAN ids are associated with both namespaces
    - The VLAN id is used to determine which direction the traffic traverses
      the VNFS
* Performs a payload scan searching for the token 'boom' when found the
  packets are dropped
* Performs packet rate metering on TCP traffic

The folder "dataplane" include all the dataplane files including:
* P4 source
* C sandbox source
* P4 configuration files
* Netronome SDK6 Programmer Studio project file
* Command line building Makefile (you will need the NFP SDK Toolchain installed)
* Command line loading script

The folder "host" contains all the host files to drive the demo. It also
includes an RTE startup script that is geared towards running VFIO in VMs.

Note that no VMs are provided for the VNFs.

The license for all provided software can be found in LICENSE.txt.

For more information about Netronome SmartNICs see open-nfp.org
