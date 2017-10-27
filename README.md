# nsotools
Tools for developing with NSO

## nso-install.sh
Usage: nso-install -v NSO-VERSION -d NSO-INSTALL-BASE-DIR [-r NSO-BINARY-REPO-URL] -u USERNAME [-p PASSWORD] [-n NED-NAME]*
Support OS versions: MACOS, CentOS

This script will attempt to install the NSO version indicated with the local-install option
in the directory NSO-INSTALL-BASE-DIR/NSO-VERSION
and the latest NEDs for the version of NSO specified.  You can specify 
multiple NEDs with the -n option.  Note this does not overwrite the NSO
installer NEDs but instead places them in a seperate location.  Based on the operating system
it will also attempt to install or update relevent packages that NSO relies on.

If the version of NSO is already installed or the latest version of the NED is already
present then no action is taken.  This can be run multiple times and only new items will
be downloaded and installed.

If you have a password with special characters such as pass!word escape
the special characters, ie. -p pass\\!word when running the script
