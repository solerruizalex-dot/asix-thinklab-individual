# 2026-11-23 11:44:11 by RouterOS 7.24.6
# software id = IUGE-FPAV
#
/interface ethernet
set [ find default-name=ether1 ] advertise=\
    10M-baseT-half,10M-baseT-full,100M-baseT-half,100M-baseT-full \
    disable-running-check=no
set [ find default-name=ether2 ] advertise=\
    10M-baseT-half,10M-baseT-full,100M-baseT-half,100M-baseT-full \
    disable-running-check=no
/ip pool
add name=pool_lan ranges=192.168.36.100-192.168.36.200
/ip dhcp-server
add address-pool=pool_lan interface=ether2 name=dhcp_lan
/user group
add comment="solo lectura para copias desde el NAS" name=copias policy="ssh,ft\
    p,read,test,sensitive,!local,!telnet,!reboot,!write,!policy,!winbox,!passw\
    ord,!web,!sniff,!api,!romon,!rest-api"
/ip settings
set ipv4-high-fragment-thresh=32.0MiB max-neighbor-entries=16384
/ipv6 settings
set max-neighbor-entries=16384 min-neighbor-entries=4096 \
    soft-max-neighbor-entries=8192
/ip address
add address=192.168.36.1/24 comment="LAN individual" interface=ether2 \
    network=192.168.36.0
/ip dhcp-client
add interface=ether1 name=client1
/ip dhcp-server lease
add address=192.168.36.150 comment="pc-informatica (cliente Linux)" \
    mac-address=08:00:27:AA:51:50 server=dhcp_lan
/ip dhcp-server network
add address=192.168.36.0/24 dns-server=192.168.36.21,192.168.36.1 domain=\
    alexsoler.lan gateway=192.168.36.1
/ip dns
set allow-remote-requests=yes servers=1.1.1.1,8.8.8.8
/ip firewall filter
add action=accept chain=input comment="IN: conexiones establecidas" \
    connection-state=established,related
add action=drop chain=input comment="IN: invalidas" connection-state=invalid
add action=accept chain=input comment="IN: ping" protocol=icmp
add action=accept chain=input comment="IN: cliente DHCP WAN" dst-port=68 \
    in-interface=ether1 protocol=udp
add action=accept chain=input comment="IN: gestion y DNS desde la LAN" \
    in-interface=ether2
add action=accept chain=input comment="IN: SSH desde el anfitrion" dst-port=\
    22 in-interface=ether1 protocol=tcp src-address=10.0.2.2
add action=drop chain=input comment="IN: resto descartado" log=yes \
    log-prefix=MK-IN-DROP
add action=accept chain=forward comment="FWD: establecidas" connection-state=\
    established,related
add action=drop chain=forward comment="FWD: invalidas" connection-state=\
    invalid
add action=drop chain=forward comment=\
    "FWD: prueba bloqueo telnet/SMB hacia fuera" dst-port=23,445 \
    in-interface=ether2 log=yes log-prefix=MK-BLOQ out-interface=ether1 \
    protocol=tcp
add action=accept chain=forward comment="FWD: LAN a Internet" in-interface=\
    ether2 out-interface=ether1
add action=drop chain=forward comment="FWD: resto descartado" log=yes \
    log-prefix=MK-FWD-DROP
/ip firewall nat
add action=masquerade chain=srcnat out-interface=ether1
/ip service
set ftp disabled=yes
set telnet disabled=yes
set api disabled=yes
set api-ssl disabled=yes
/system clock
set time-zone-name=Europe/Madrid
/system identity
set name=MikroTik-AlexSoler
/system package update
set channel=long-term
/system scheduler
add comment="copia local diaria, el NAS se la lleva a las 23:00" !days \
    interval=1d name=backup-diario on-event="/system backup save name=mikrotik\
    -diario dont-encrypt=yes; /export file=mikrotik-diario" policy=\
    ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon \
    start-date=2026-11-22 start-time=22:30:00
