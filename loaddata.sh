#!/bin/sh 

ncs_cli << EOF
config
load merge $1
commit
exit no-confirm
exit
EOF

