#!/bin/sh 

ncsdir=/opt/ncs/current
confdir=/etc/ncs
rundir=/var/opt/ncs
logdir=/var/log/ncs

NCS_CONFIG_DIR=${confdir}
NCS_RUN_DIR=${rundir}
NCS_LOG_DIR=${logdir}
export NCS_CONFIG_DIR NCS_RUN_DIR NCS_LOG_DIR

${ncsdir}/bin/ncs_cli --noaaa << EOF
config
load merge $1
commit dry-run
commit
exit no-confirm
exit
EOF

