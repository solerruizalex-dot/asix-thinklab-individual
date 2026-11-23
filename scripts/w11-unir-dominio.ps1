# w11-unir-dominio.ps1 - Álex Soler Ruiz
# Une el Windows 11 de Administración al dominio alexsoler.lan.
# El DNS (192.168.30.21) ya llega por el DHCP del MikroTik; si no, el equipo no encuentra el dominio.
# La contraseña no va en el script: antes de lanzarlo  $env:CLAVE = '...'
if (-not $env:CLAVE) { throw 'Falta la variable de entorno CLAVE' }
$ErrorActionPreference = 'Stop'
$nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
Get-NetIPConfiguration -InterfaceIndex $nic.ifIndex | Format-List IPv4Address, IPv4DefaultGateway, DNSServer
Resolve-DnsName alexsoler.lan -Type A | Format-Table Name, IPAddress
Resolve-DnsName _ldap._tcp.dc._msdcs.alexsoler.lan -Type SRV | Format-Table Name, NameTarget, Port

$cred = New-Object System.Management.Automation.PSCredential('ALEXSOLER\adm.alex',
        (ConvertTo-SecureString $env:CLAVE -AsPlainText -Force))
Add-Computer -DomainName 'alexsoler.lan' -NewName 'PC-ADMIN01' -OUPath 'OU=Equipos,OU=Empresa,DC=alexsoler,DC=lan' `
             -Credential $cred -Force -Restart
