# dc-05-exclusion-defender.ps1 - Álex Soler Ruiz
# La copia del estado del sistema tardaba 41 min porque Defender (MsMpEng) analizaba cada fichero
# que leía wbengine. Excluyo SOLO el motor de copia y la carpeta donde escribe la copia,
# no el disco C: ni la carpeta del sistema: el resto del servidor sigue analizándose igual.
Add-MpPreference -ExclusionProcess 'C:\Windows\System32\wbengine.exe'
Add-MpPreference -ExclusionPath 'E:\WindowsImageBackup'
Get-MpPreference | Select-Object ExclusionProcess, ExclusionPath | Format-List
Get-MpComputerStatus | Select-Object RealTimeProtectionEnabled, AntivirusEnabled | Format-List
