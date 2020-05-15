Function SetTSVariable([string]$path)
{
    $tsEnv = New-Object -COMobject Microsoft.SMS.TSEnvironment -ErrorAction SilentlyContinue
    If ($tsEnv)
    {
        $tsEnv.Value("Win10Driver") = $path
    }
}

Function CopyDrivers([string]$path)
{
    If (Test-Path $path)
    {
        Write-Host "Copying drivers from $path to $driverCache"
        Copy-Item "$path" -Destination "$driverCache" -Recurse
    }
}

Start-Transcript -Path "C:\Windows\Temp\OSD_CopyDrivers_W10.log" -force -append

# Set driver store location
$driverStore = "\\SERVER\SHARE\OSDDrivers\x64\Windows 10"

# Create cache folder and set Task Sequence variable
$driverCache = "C:\_SMSTaskSequence\Packages\OSDDrivers"
New-Item -Path $driverCache -ItemType directory -Force | Out-Null
SetTSVariable($driverCache)

# Get computer information from WMI
$query = "Select * from Win32_ComputerSystem"
$getComputerSystem = Get-WMIObject -Query $query
If ($getComputerSystem)
{
    $computerMake = $getComputerSystem.Manufacturer
    $computerModel = $getComputerSystem.Model
    Write-Host "Computer make and model: $computerMake $computerModel"
}
Else
{
    Write-Host "Error: Unable to query WMI for computer information"
    Exit
}


# Copy drivers for supported models
If ($computerMake -like "Dell*")
{
    $driverStore = "$driverStore\Dell"

    If ($computerModel -like "*E5470*")
    {
        $driverStore = "$driverStore\E5470"
        $copyDrivers = 1
    }
    ElseIf ($computerModel -like "*E5570*")
    {
        $driverStore = "$driverStore\E5570"
        $copyDrivers = 1
    }
    ElseIf ($computerModel -like "*7040*")
    {
        $driverStore = "$driverStore\7040"
        $copyDrivers = 1
    }
    ElseIf ($computerModel -like "*E7270*")
    {
        $driverStore = "$driverStore\E7270"
        $copyDrivers = 1
    }
    ElseIf ($computerModel -like "*E6440*")
    {
        $driverStore = "$driverStore\E6440"
        $copyDrivers = 1
    }
    ElseIf ($computerModel -like "*9020*")
    {
        $driverStore = "$driverStore\9020"
        $copyDrivers = 1
    }
    ElseIf ($computerModel -like "*7050*")
    {
        $driverStore = "$driverStore\7050"
        $copyDrivers = 1
    }
    ElseIf ($computerModel -like "*7280*")
    {
        $driverStore = "$driverStore\7280"
        $copyDrivers = 1
    }
    ElseIf ($computerModel -like "*5480*")
    {
        $driverStore = "$driverStore\5480"
        $copyDrivers = 1
    }
    Else
    {
        # No drivers available
    }
}

If ($copyDrivers = 1)
{
    CopyDrivers($driverStore)
}

Stop-Transcript
