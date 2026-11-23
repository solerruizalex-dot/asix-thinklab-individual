# dc-02-estructura.ps1 - Álex Soler Ruiz
# Unidades organizativas, grupos y usuarios de prueba del dominio alexsoler.lan
# Los usuarios son ficticios. La contraseña inicial obliga a cambiarla en el primer inicio.
# La contraseña no va en el script: antes de lanzarlo  $env:CLAVE = '...'
if (-not $env:CLAVE -or -not $env:CLAVE_INICIAL) { throw 'Faltan las variables de entorno CLAVE y CLAVE_INICIAL' }
$ErrorActionPreference = 'Continue'
Import-Module ActiveDirectory
$base = 'DC=alexsoler,DC=lan'

# DNS: el propio DC primero, reenviadores hacia fuera
Set-DnsClientServerAddress -InterfaceAlias LAN -ServerAddresses 127.0.0.1, 192.168.30.1
Set-DnsServerForwarder -IPAddress 192.168.30.1, 1.1.1.1
if (-not (Get-DnsServerZone -Name '30.168.192.in-addr.arpa' -ErrorAction SilentlyContinue)) {
    Add-DnsServerPrimaryZone -NetworkId '192.168.30.0/24' -ReplicationScope Forest
}
# registros de los equipos con IP fija
$fijos = @{ 'mikrotik'='192.168.30.1'; 'opnsense'='192.168.30.2'; 'debian-nft'='192.168.30.3';
            'truenas'='192.168.30.20'; 'serveis'='192.168.30.22'; 'dades'='192.168.30.23';
            'pve1'='192.168.30.32'; 'pve2'='192.168.30.33'; 'pve3'='192.168.30.34' }
foreach ($h in $fijos.Keys) {
    if (-not (Get-DnsServerResourceRecord -ZoneName alexsoler.lan -Name $h -ErrorAction SilentlyContinue)) {
        Add-DnsServerResourceRecordA -ZoneName alexsoler.lan -Name $h -IPv4Address $fijos[$h] -CreatePtr
    }
}

# OUs
$ous = 'Empresa', 'Direccion', 'Administracion', 'Comercial', 'Produccion', 'Informatica', 'Equipos', 'Servidores'
function Nueva-OU($n, $p) { if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$n'" -SearchBase $p -SearchScope OneLevel)) { New-ADOrganizationalUnit -Name $n -Path $p } }
Nueva-OU 'Empresa' $base
$emp = "OU=Empresa,$base"
foreach ($ou in $ous[1..7]) { Nueva-OU $ou $emp }

# los equipos nuevos que se unan al dominio caen en OU=Equipos en vez de en Computers
redircmp "OU=Equipos,$emp" | Out-Null

# grupos y un usuario por departamento
# contraseña inicial de los usuarios de prueba: también por variable de entorno
$pass = ConvertTo-SecureString $env:CLAVE_INICIAL -AsPlainText -Force
$usuarios = @(
    @{ou='Direccion';      sam='l.marti';    nom='Laura';  ape='Martí'},
    @{ou='Administracion'; sam='administracion'; nom='Usuario'; ape='Administración'},
    @{ou='Comercial';      sam='p.ferrer';   nom='Pau';    ape='Ferrer'},
    @{ou='Produccion';     sam='j.navarro';  nom='Joan';   ape='Navarro'},
    @{ou='Informatica';    sam='a.soler';    nom='Álex';   ape='Soler'}
)
foreach ($d in 'Direccion', 'Administracion', 'Comercial', 'Produccion', 'Informatica') {
    if (-not (Get-ADGroup -Filter "Name -eq 'G_$d'")) { New-ADGroup -Name "G_$d" -GroupScope Global -GroupCategory Security -Path "OU=$d,$emp" }
}
foreach ($u in $usuarios) {
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($u.sam)'")) {
        New-ADUser -SamAccountName $u.sam -UserPrincipalName "$($u.sam)@alexsoler.lan" `
            -Name "$($u.nom) $($u.ape)" -GivenName $u.nom -Surname $u.ape -Department $u.ou `
            -Path "OU=$($u.ou),$emp" -AccountPassword $pass -Enabled $true -ChangePasswordAtLogon $false
    }
    Add-ADGroupMember -Identity "G_$($u.ou)" -Members $u.sam
}
# cuenta de administración personal (no se trabaja con Administrador)
if (-not (Get-ADUser -Filter "SamAccountName -eq 'adm.alex'")) {
    New-ADUser -SamAccountName 'adm.alex' -UserPrincipalName 'adm.alex@alexsoler.lan' -Name 'adm.alex' `
        -Description 'Cuenta de administracion de Alex Soler' -Path "OU=Informatica,$emp" `
        -AccountPassword (ConvertTo-SecureString $env:CLAVE -AsPlainText -Force) -Enabled $true
}
# el nombre del grupo cambia con el idioma (Admins. del dominio / Domain Admins): lo busco por SID
$domAdmins = Get-ADGroup -Filter "SID -eq '$((Get-ADDomain).DomainSID)-512'"
Add-ADGroupMember -Identity $domAdmins -Members 'adm.alex'

Get-ADOrganizationalUnit -Filter * -SearchBase $emp | Select-Object Name | Format-Table -AutoSize
Get-ADUser -Filter * -SearchBase $emp -Properties Department | Select-Object SamAccountName, Name, Department | Format-Table -AutoSize
