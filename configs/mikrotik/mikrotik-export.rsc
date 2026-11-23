# 2026-11-22 23:03:43 by RouterOS 7.24.6
# software id = IUGE-FPAV
#
/interface ethernet set [ find default-name=ether1 ] disable-running-check=no
/interface ethernet set [ find default-name=ether2 ] disable-running-check=no
/ip pool add name=pool_lan ranges=192.168.30.100-192.168.30.200
/ip dhcp-server add address-pool=pool_lan interface=ether2 name=dhcp_lan
/user group add comment="solo lectura para copias desde el NAS" name=copias policy=ssh,ftp,read,test,sensitive,!local,!telnet,!reboot,!write,!policy,!winbox,!password,!web,!sniff,!api,!romon,!rest-api
/ip settings set ipv4-high-fragment-thresh=32.0MiB max-neighbor-entries=16384
/ipv6 settings set max-neighbor-entries=16384 min-neighbor-entries=4096 soft-max-neighbor-entries=8192
/ip address add address=192.168.30.1/24 interface=ether2 network=192.168.30.0
/ip dhcp-client add interface=ether1 name=client1
/ip dhcp-server lease add address=192.168.30.150 comment="pc-informatica (cliente Linux)" mac-address=08:00:27:AA:51:50 server=dhcp_lan
/ip dhcp-server network add address=192.168.30.0/24 dns-server=192.168.30.21,192.168.30.1 domain=alexsoler.lan gateway=192.168.30.1
/ip dns set allow-remote-requests=yes servers=1.1.1.1,8.8.8.8
/ip firewall filter add action=accept chain=input comment="IN: conexiones establecidas" connection-state=established,related
/ip firewall filter add action=drop chain=input comment="IN: invalidas" connection-state=invalid
/ip firewall filter add action=accept chain=input comment="IN: ping" protocol=icmp
/ip firewall filter add action=accept chain=input comment="IN: cliente DHCP WAN" dst-port=68 in-interface=ether1 protocol=udp
/ip firewall filter add action=accept chain=input comment="IN: gestion y DNS desde la LAN" in-interface=ether2
/ip firewall filter add action=accept chain=input comment="IN: SSH desde el anfitrion" dst-port=22 in-interface=ether1 protocol=tcp src-address=10.0.2.2
/ip firewall filter add action=drop chain=input comment="IN: resto descartado" log=yes log-prefix=MK-IN-DROP
/ip firewall filter add action=accept chain=forward comment="FWD: establecidas" connection-state=established,related
/ip firewall filter add action=drop chain=forward comment="FWD: invalidas" connection-state=invalid
/ip firewall filter add action=drop chain=forward comment="FWD: prueba bloqueo telnet/SMB hacia fuera" dst-port=23,445 in-interface=ether2 log=yes log-prefix=MK-BLOQ out-interface=ether1 protocol=tcp
/ip firewall filter add action=accept chain=forward comment="FWD: LAN a Internet" in-interface=ether2 out-interface=ether1
/ip firewall filter add action=drop chain=forward comment="FWD: resto descartado" log=yes log-prefix=MK-FWD-DROP
/ip firewall nat add action=masquerade chain=srcnat out-interface=ether1
/ip service set ftp disabled=yes
/ip service set telnet disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/system clock set time-zone-name=Europe/Madrid
/system identity set name=MikroTik-AlexSoler
/system package update set channel=long-term
/system scheduler add comment="copia local diaria, el NAS se la lleva a las 23:00" !days interval=1d name=backup-diario on-event="/system backup save name=mikrotik-diario dont-encrypt=yes; /export file=mikrotik-diario" policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon start-date=2026-11-22 start-time=22:30:00
