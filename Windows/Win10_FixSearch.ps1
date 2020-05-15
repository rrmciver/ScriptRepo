$ErrorActionPreferences = "Continue"
Start-Transcript -path C:\Windows\Temp\RepairSearch.txt -append
Add-AppxPackage -DisableDevelopmentMode -Register "C:\Windows\SystemApps\Microsoft.Windows.Cortana_cw5n1h2txyewy\AppxManifest.xml"
Stop-Transcript