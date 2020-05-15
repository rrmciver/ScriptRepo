$ErrorActionPreferences = "Continue"
Start-Transcript -path C:\Windows\Temp\RepairStartMenu.txt -append
Add-AppxPackage -DisableDevelopmentMode -Register "C:\Windows\SystemApps\ShellExperienceHost_cw5n1h2txyewy\AppxManifest.xml"
Stop-Transcript