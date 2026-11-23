# dc-06-cambio-red.ps1 - Álex Soler Ruiz
# Cambia el controlador de dominio de la red 192.168.30.0/24 a 192.168.36.0/24 (la que me corresponde en el
# individual) sin rehacer el dominio. Mantiene el último octeto de cada equipo.
# Se ejecuta en el DC como administrador del dominio (yo lo lancé con VBoxManage guestcontrol: no depende de la red).
$ErrorActionPreference = 'Stop'
$viejo = '192.168.30.'; $nuevo = '192.168.36.'

"== 1. IP del DC: .21 en la red nueva, puerta .1 y DNS él mismo + MikroTik"
if (Get-NetIPAddress -IPAddress "${viejo}21" -ErrorAction SilentlyContinue) {   # así el script se puede repetir
    Get-NetRoute -InterfaceAlias LAN -DestinationPrefix 0.0.0.0/0 -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
    New-NetIPAddress -InterfaceAlias LAN -IPAddress "${nuevo}21" -PrefixLength 24 -DefaultGateway "${nuevo}1" | Out-Null
    Remove-NetIPAddress -InterfaceAlias LAN -IPAddress "${viejo}21" -Confirm:$false
}
Set-DnsClientServerAddress -InterfaceAlias LAN -ServerAddresses 127.0.0.1, "${nuevo}1"

"== 2. Servidor DNS: escuchar en la IP nueva (estaba fijado a la vieja) y reenviadores"
$s = Get-DnsServerSetting -All -WarningAction SilentlyContinue
$s.ListeningIPAddress = @("${nuevo}21")
Set-DnsServerSetting -InputObject $s -WarningAction SilentlyContinue
Set-DnsServerForwarder -IPAddress "${nuevo}1", 1.1.1.1
Restart-Service DNS
Start-Sleep 20   # sin esta espera, el primer registro falló con el error 9607: las zonas aún se estaban cargando

"== 3. Zona inversa nueva y registros A (con su PTR) de los equipos con IP fija"
if (-not (Get-DnsServerZone -Name '36.168.192.in-addr.arpa' -ErrorAction SilentlyContinue)) {
    Add-DnsServerPrimaryZone -NetworkId '192.168.36.0/24' -ReplicationScope Forest -DynamicUpdate Secure
}
$fijos = @{ 'mikrotik'='1'; 'opnsense'='2'; 'debian-nft'='3'; 'truenas'='20'; 'serveis'='22'; 'dades'='23';
            'pve1'='32'; 'pve2'='33'; 'pve3'='34'; 'pc-informatica'='150' }
foreach ($n in $fijos.Keys) {
    Get-DnsServerResourceRecord -ZoneName alexsoler.lan -Name $n -RRType A -ErrorAction SilentlyContinue |
        Remove-DnsServerResourceRecord -ZoneName alexsoler.lan -Force
    Add-DnsServerResourceRecordA -ZoneName alexsoler.lan -Name $n -IPv4Address ($nuevo + $fijos[$n]) -CreatePtr
}
# el cliente Windows (DHCP) se volverá a registrar solo con su IP nueva
Get-DnsServerResourceRecord -ZoneName alexsoler.lan -Name 'PC-ADMIN01' -RRType A -ErrorAction SilentlyContinue |
    Remove-DnsServerResourceRecord -ZoneName alexsoler.lan -Force
# registros del propio DC con la IP vieja (@, dc01-alex, DomainDnsZones, ForestDnsZones): fuera, netlogon pone los nuevos
Get-DnsServerResourceRecord -ZoneName alexsoler.lan -RRType A | Where-Object { $_.RecordData.IPv4Address -like "${viejo}*" } |
    Remove-DnsServerResourceRecord -ZoneName alexsoler.lan -Force
if (Get-DnsServerZone -Name '30.168.192.in-addr.arpa' -ErrorAction SilentlyContinue) {
    Remove-DnsServerZone -Name '30.168.192.in-addr.arpa' -Force
}

"== 4. Scripts del DC que apuntan al NAS por IP"
Get-ChildItem C:\scripts -Filter *.ps1 | ForEach-Object {
    (Get-Content $_.FullName -Raw).Replace($viejo, $nuevo) | Set-Content $_.FullName -Encoding UTF8
}

"== 5. El DC vuelve a registrar sus registros (A, SRV del dominio) con la IP nueva"
ipconfig /registerdns | Out-Null
Restart-Service Netlogon
Start-Sleep 15
Get-NetIPAddress -InterfaceAlias LAN -AddressFamily IPv4 | Format-Table IPAddress, PrefixLength -AutoSize
Get-DnsServerResourceRecord -ZoneName alexsoler.lan -RRType A | Format-Table HostName, @{n='IP';e={$_.RecordData.IPv4Address}} -AutoSize
Resolve-DnsName _ldap._tcp.dc._msdcs.alexsoler.lan -Type SRV | Format-Table Name, NameTarget, Port -AutoSize
