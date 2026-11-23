# w11-copias.ps1 - Álex Soler Ruiz
# Copia de los datos de usuario del PC de Administración al NAS.
# No se hace imagen del sistema: un cliente se reinstala o se clona en menos tiempo
# y la configuración le llega del dominio. Lo que no se puede recuperar son los ficheros.
$nas  = '\\truenas.alexsoler.lan\copias-windows'
$pass = Get-Content 'C:\scripts\.nas'
$dest = "$nas\$env:COMPUTERNAME"
net use $nas /user:copias $pass /persistent:no | Out-Null
foreach ($perfil in Get-ChildItem 'C:\Users' -Directory | Where-Object { $_.Name -notin 'Public', 'Default', 'Default User', 'All Users' }) {
    foreach ($c in 'Desktop', 'Documents', 'Downloads') {
        $src = Join-Path $perfil.FullName $c
        if (Test-Path $src) {
            robocopy $src "$dest\$($perfil.Name)\$c" /MIR /R:1 /W:1 /NP /NFL /NDL /LOG+:C:\scripts\copias.log | Out-Null
        }
    }
}
"$(Get-Date -Format s) copia de perfiles en $dest (codigo robocopy $LASTEXITCODE)" | Add-Content C:\scripts\copias.log
net use $nas /delete /y | Out-Null
