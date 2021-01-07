#!/bin/sh 

ncs_cli --noaaa << EOF
config
load merge $1
commit dry-run
commit
exit no-confirm
exit
EOF

