$ErrorActionPreferences = "Continue"
Start-Transcript -path C:\Windows\Temp\RepairAppX.txt -append
Get-AppxPackage -AllUsers | foreach {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -Verbose}
Stop-Transcript