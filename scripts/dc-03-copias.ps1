# dc-03-copias.ps1 - Álex Soler Ruiz
# Copia del controlador de dominio al NAS (\\192.168.30.20\copias-windows)
#  - Estado del sistema (AD, SYSVOL, registro, arranque): es lo que hace falta para
#    recuperar el dominio. Una imagen completa de C: no compensa: reinstalar Windows
#    tarda menos que restaurar 20 GB por USB, y lo que tiene valor es el estado del sistema.
#  - Exportaciones legibles (GPO, usuarios, zona DNS): sirven para consultar o recuperar
#    un objeto suelto sin restaurar el DC entero.
# Se ejecuta como tarea programada (SYSTEM) cada noche.
$ErrorActionPreference = 'Continue'
$nas   = '\\192.168.30.20\copias-windows'
$user  = 'copias'
$pass  = Get-Content 'C:\scripts\.nas' -ErrorAction Stop   # fichero con permisos solo para administradores
$hoy   = Get-Date -Format 'yyyy-MM-dd_HHmm'
$log   = "C:\scripts\copias.log"
function Log($m) { "$(Get-Date -Format s)  $m" | Tee-Object -FilePath $log -Append }

net use $nas /user:$user $pass /persistent:no | Out-Null

# 1) exportaciones legibles
$exp = "$nas\DC01-export\$hoy"
New-Item -ItemType Directory -Path $exp -Force | Out-Null
Backup-GPO -All -Path (New-Item -ItemType Directory "$exp\gpo" -Force).FullName | Out-Null
Get-ADUser -Filter * -Properties Department, MemberOf, Enabled |
    Select-Object SamAccountName, Name, Department, Enabled, DistinguishedName |
    Export-Csv "$exp\usuarios.csv" -NoTypeInformation -Encoding UTF8
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName | Export-Csv "$exp\ous.csv" -NoTypeInformation -Encoding UTF8
dnscmd /ZoneExport alexsoler.lan "export-alexsoler.lan.dns" | Out-Null
Copy-Item "$env:SystemRoot\System32\dns\export-alexsoler.lan.dns" $exp
Log "exportaciones copiadas a $exp"

# 2) estado del sistema con Windows Server Backup
#    Primero a un disco local dedicado (E:) y después se replica al NAS.
#    Directamente contra el recurso SMB no avanzaba: Defender escaneaba cada fichero
#    leído y en 30 minutos solo había escrito 1,6 MB. En local tarda unos minutos.
#    wbadmin guarda versiones en E:; en el NAS el historial lo dan las instantáneas ZFS.
$r = wbadmin start systemstatebackup -backupTarget:E: -quiet 2>&1
$rc = $LASTEXITCODE
# OJO: el texto "se completó correctamente" lo escribe wbadmin también cuando la copia se cancela;
# lo fiable es el código de salida (0 = copia correcta) y el evento 4 del registro Microsoft-Windows-Backup.
if ($rc -eq 0) {
    Log "wbadmin: copia de estado del sistema CORRECTA"
    robocopy 'E:\WindowsImageBackup' "$nas\DC01-systemstate\WindowsImageBackup" /MIR /R:1 /W:1 /NP /NFL /NDL | Out-Null
    Log "robocopy al NAS terminado (codigo $LASTEXITCODE; 0-7 es correcto)"
} else {
    Log "wbadmin: FALLO (codigo $rc): $(($r | Select-Object -Last 3) -join ' ')"
    Log "no replico al NAS una copia que no ha terminado bien"
}

net use $nas /delete /y | Out-Null
