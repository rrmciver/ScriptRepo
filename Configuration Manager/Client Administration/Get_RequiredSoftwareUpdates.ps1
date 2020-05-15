$computerName = Read-Host "Computer Name"

Get-WmiObject -ComputerName $computerName -query "SELECT * FROM CCM_SoftwareUpdate" -namespace "ROOT\ccm\ClientSDK" | Select -Property PSComputerName, Name, ArticleID