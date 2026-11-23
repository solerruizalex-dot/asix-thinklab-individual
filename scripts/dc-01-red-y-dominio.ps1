# dc-01-red-y-dominio.ps1 - Álex Soler Ruiz
# Deja el servidor con IP fija y lo promociona a primer DC del bosque alexsoler.lan
# Al terminar la promoción el servidor se reinicia solo.
# La contraseña no va en el script: antes de lanzarlo  $env:CLAVE = '...'
if (-not $env:CLAVE) { throw 'Falta la variable de entorno CLAVE' }
$ErrorActionPreference = 'Stop'

# --- red ---
$nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
if ($nic.Name -ne 'LAN') { Rename-NetAdapter -Name $nic.Name -NewName 'LAN' }
Set-NetIPInterface -InterfaceAlias LAN -Dhcp Disabled
Get-NetIPAddress -InterfaceAlias LAN -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
Remove-NetRoute -InterfaceAlias LAN -DestinationPrefix 0.0.0.0/0 -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceAlias LAN -IPAddress 192.168.30.21 -PrefixLength 24 -DefaultGateway 192.168.30.1 | Out-Null
# hasta que sea DC pregunta al MikroTik; despues de promocionar se apunta a si mismo
Set-DnsClientServerAddress -InterfaceAlias LAN -ServerAddresses 192.168.30.1
Set-TimeZone -Id 'Romance Standard Time'

# --- la cuenta Administrador local pasa a ser la del dominio: necesita contraseña ---
$adm = Get-LocalUser | Where-Object { $_.SID -like '*-500' }
$adm | Set-LocalUser -Password (ConvertTo-SecureString $env:CLAVE -AsPlainText -Force)
$adm | Enable-LocalUser

# --- roles ---
Install-WindowsFeature AD-Domain-Services, DNS, Windows-Server-Backup, GPMC -IncludeManagementTools | Format-Table -AutoSize

# --- promoción ---
Import-Module ADDSDeployment
Install-ADDSForest -DomainName 'alexsoler.lan' -DomainNetbiosName 'ALEXSOLER' `
    -InstallDns -ForestMode WinThreshold -DomainMode WinThreshold `
    -SafeModeAdministratorPassword (ConvertTo-SecureString $env:CLAVE -AsPlainText -Force) `
    -Force
