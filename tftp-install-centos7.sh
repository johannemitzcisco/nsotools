#!/bin/bash
yum -y install tftp tftp-server* xinetd*
cat >/etc/xinetd.d/tftp <<EOL
# default: off
# description: The tftp server serves files using the trivial file transfer
#       protocol.  The tftp protocol is often used to boot diskless
#       workstations, download configuration files to network-aware printers,
#       and to start the installation process for some operating systems.
service tftp
{
        socket_type             = dgram
        protocol                = udp
        wait                    = yes
        user                    = root
        server                  = /usr/sbin/in.tftpd
        server_args             = -c -s /var/lib/tftpboot
        disable                 = no
        per_source              = 11
        cps                     = 100 2
        flags                   = IPv4
}
EOL
if [ -z /var/lib/tftpboot ]; then mkdir /var/lib/tftpboot; fi
chmod 777 /var/lib/tftpboot
#iptables -I INPUT -p udp –dport 69 -j ACCEPT
systemctl start xinetd
systemctl start tftp
systemctl enable xinetd
systemctl enable tftp
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
echo "REBOOT REQUIRED for tftp to function"
