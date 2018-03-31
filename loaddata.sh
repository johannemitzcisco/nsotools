#!/bin/sh 

ncs_cli -u admin << EOF
config
load merge $1
commit dry-run
commit
exit no-confirm
exit
EOF

