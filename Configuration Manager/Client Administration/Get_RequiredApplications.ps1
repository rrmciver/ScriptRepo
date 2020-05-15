Clear-Host
$computerName = Read-Host "Compuer Name"
Get-WmiObject -ComputerName $computerName -query "SELECT * FROM CCM_Application" -namespace "ROOT\ccm\ClientSDK" | Where-Object {$_.InstallState -eq "NotInstalled"} | Select -Property PSComputerName, FullName, InstallState