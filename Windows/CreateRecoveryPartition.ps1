Start-Transcript "C:\Windows\Temp\CreateRecoveryPartition.log" -Force

"Getting OS partition info..."
$partInfo = Get-PartitionSupportedSize -DriveLetter "C"
$partInfo

"Calculating free space..."
$freeSpace = ($($partInfo.SizeMax) - $($partInfo.SizeMin)) / 1MB
"$freeSpace MB is available"

If($freeSpace -gt 1024)
{
    "At least 1GB of free disk space is available."
    "Calculating new partition size..."
    $newSize = $partInfo.SizeMax - 500MB
    "New partition size will be: $newSize MB"

    Try{
        "Resizing OS partition..."
        Resize-Partition -DriveLetter "C" -Size $newSize -ErrorAction Stop | Out-Null

        "Getting disk number of OS partition..."
        $diskNum = (Get-Partition | Where-Object DriveLetter -eq "C" | Get-Disk).Number
        "Disk: $diskNum"

        "Creating new recovery partition..."
        $recPart = New-Partition -DiskNumber $diskNum -Size 499MB -AssignDriveLetter -ErrorAction Stop
        
        "Formatting the partition..."
        Format-Volume -DriveLetter $recPart.DriveLetter -FileSystem NTFS -NewFileSystemLabel "Recovery" -ErrorAction Stop

        "Creating folder structure for WinRE..."
        New-Item "$($recPart.DriveLetter):\Recovery\WindowsRE" -ItemType Directory -ErrorAction Stop | Out-Null

        "Copying winre.wim..."
        Copy-Item "$PSScriptRoot\Winre.wim" -Destination "$($recPart.DriveLetter):\Recovery\WindowsRE\" -ErrorAction Stop | Out-Null
    }
    Catch
    {
        $Error[0]
        EXIT
    }

    "Getting current recovery image status..."
    $getREStatus = reagentc /info 2>$null
    $getREStatus

    IF ($getREStatus | Select-String "Enabled")
    {
        "Disabling existing recovery image..."
        reagentc /disable 2>$null
    }

    "Setting new recovery image location..."
    $reLoc = "\\?\GLOBALROOT\device\harddisk$diskNum\partition$($recPart.PartitionNumber)\Recovery\WindowsRE"
    
    reagentc /setreimage /path $reLoc 2>$null

    "Enabling recovery image..."

    reagentc /enable 2>$null

    "Unassigning temporary drive letter..."
    $recPart | Remove-PartitionAccessPath -AccessPath "$($recPart.DriveLetter):"
}

Stop-Transcript