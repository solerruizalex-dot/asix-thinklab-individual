# dc-04-tarea-programada.ps1 - programa dc-03-copias.ps1 cada noche a las 21:30 como SYSTEM
# la clave de la cuenta 'copias' del NAS se guarda solo en el DC, nunca en el repositorio
$env:CLAVE_NAS | Set-Content 'C:\scripts\.nas'
icacls 'C:\scripts\.nas' /inheritance:r /grant:r 'Administradores:F' 'SYSTEM:F' | Out-Null
$accion  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\scripts\dc-03-copias.ps1'
$disparo = New-ScheduledTaskTrigger -Daily -At 21:30
Register-ScheduledTask -TaskName 'Copia DC al NAS' -Action $accion -Trigger $disparo -User 'SYSTEM' -RunLevel Highest -Force |
    Select-Object TaskName, State
