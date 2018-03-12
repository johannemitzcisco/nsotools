#!/bin/sh 

ncs_cli -u admin << EOF
config
load merge $1
commit
exit no-confirm
exit
EOF

