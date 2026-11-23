# red-windows.ps1 - Álex Soler Ruiz
# Comprobación de red de un equipo Windows del laboratorio (LAN 192.168.36.0/24). Misma prueba que en los Linux.
[Console]::OutputEncoding=[Text.Encoding]::UTF8
"### $env:COMPUTERNAME - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
"--- interfaces"; Get-NetIPConfiguration | ForEach-Object { "{0}: IP {1}/{2}  puerta {3}  DNS {4}  DHCP {5}" -f $_.InterfaceAlias, $_.IPv4Address.IPAddress, $_.IPv4Address.PrefixLength, $_.IPv4DefaultGateway.NextHop, (($_.DNSServer | ? AddressFamily -eq 2).ServerAddresses -join ','), (Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4).Dhcp }
"--- rutas IPv4 (route print -4)"; chcp 65001 > $null; route print -4 | Select-String -Pattern '^\s+0\.0\.0\.0|^\s+192\.168\.36\.0' | ForEach-Object { $_.Line.Trim() }
foreach ($d in '192.168.36.1','192.168.36.20','192.168.36.21') { "--- ping $d : " + ((Test-Connection $d -Count 2 -ErrorAction SilentlyContinue | Measure-Object).Count) + "/2 respuestas" }
"--- nombres: " + ((('dc01-alex','truenas','serveis','deb.debian.org') | ForEach-Object { "$_ -> " + ((Resolve-DnsName $_ -Type A -ErrorAction SilentlyContinue | ? IPAddress | Select -First 1).IPAddress) }) -join ' · ')
$t = Measure-Command { try { $r = Invoke-WebRequest http://deb.debian.org/debian/dists/trixie/Release -UseBasicParsing -TimeoutSec 15 } catch {} }
"--- Internet por HTTP (el ICMP hacia fuera lo corta la red del instituto): $($r.StatusCode), $($r.RawContentLength) bytes en $([math]::Round($t.TotalSeconds,2)) s"
"--- tracert -d -h 4 1.1.1.1"; tracert -d -h 4 -w 1000 1.1.1.1 | Select-String -Pattern '^\s+\d' | ForEach-Object { $_.Line.Trim() }
""
