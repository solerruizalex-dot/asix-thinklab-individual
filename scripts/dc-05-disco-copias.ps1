# dc-05-disco-copias.ps1 - prepara el segundo disco del DC como E: (copias locales)
$d = Get-Disk | Where-Object PartitionStyle -eq 'RAW' | Select-Object -First 1
if ($d) {
    Initialize-Disk -Number $d.Number -PartitionStyle GPT
    New-Partition -DiskNumber $d.Number -UseMaximumSize -DriveLetter E | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'COPIAS' -Confirm:$false
}
Get-Volume -DriveLetter E | Format-Table DriveLetter, FileSystemLabel, FileSystem, Size, SizeRemaining
