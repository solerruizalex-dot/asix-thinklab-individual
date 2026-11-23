# windows-actualizar.ps1 - Álex Soler Ruiz
# Busca, descarga e instala las actualizaciones de Windows Update con la API COM que trae Windows
# (sin módulos externos). No instala actualizaciones de versión (feature updates): esas se prueban aparte.
# Se lanza como tarea programada (SYSTEM) para que no dependa de la sesión. Registro en C:\scripts\wu.log
$log = 'C:\scripts\wu.log'
function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Add-Content $log -Encoding UTF8 }
$v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
Log "ANTES: $($v.ProductName) $($v.DisplayVersion) compilación $($v.CurrentBuild).$($v.UBR)"
$ses = New-Object -ComObject Microsoft.Update.Session
$bus = $ses.CreateUpdateSearcher()
$res = $bus.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
$lista = New-Object -ComObject Microsoft.Update.UpdateColl
foreach ($u in $res.Updates) {
    $esVersion = $u.Categories | Where-Object { $_.Name -match 'Upgrades|Actualizaciones de características' }
    if ($esVersion) { Log "OMITIDA (cambio de versión): $($u.Title)"; continue }
    if (-not $u.EulaAccepted) { $u.AcceptEula() }
    Log "PENDIENTE: $($u.Title)  [$([math]::Round($u.MaxDownloadSize/1MB)) MB]"
    [void]$lista.Add($u)
}
if ($lista.Count -eq 0) { Log 'No hay actualizaciones pendientes'; exit 0 }
$t = Get-Date
$d = $ses.CreateUpdateDownloader(); $d.Updates = $lista; $rd = $d.Download()
Log "Descarga terminada: código $($rd.ResultCode) (2 = correcto) en $([int]((Get-Date)-$t).TotalMinutes) min"
$t = Get-Date
$i = $ses.CreateUpdateInstaller(); $i.Updates = $lista; $ri = $i.Install()
for ($k = 0; $k -lt $lista.Count; $k++) { Log ("  {0} -> {1}" -f $lista.Item($k).Title, $ri.GetUpdateResult($k).ResultCode) }
Log "Instalación terminada: código $($ri.ResultCode) en $([int]((Get-Date)-$t).TotalMinutes) min · necesita reiniciar: $($ri.RebootRequired)"
Log 'FIN'
