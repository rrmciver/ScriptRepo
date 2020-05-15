Import-Module "$env:SMS_ADMIN_UI_PATH\..\configurationmanager.psd1"

$siteCode = $(Get-WMIObject -ComputerName "$ENV:ComputerName" -NameSpace "root\sms" -Class "SMS_ProviderLocation").SiteCode
Set-Location "$($siteCode):"

New-CMStatusMessageQuery -Name "Failed to execute SQL command (601)" -Expression "query" 
