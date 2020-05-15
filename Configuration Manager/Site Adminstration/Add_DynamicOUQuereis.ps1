Import-Module "$env:SMS_ADMIN_UI_PATH\..\configurationmanager.psd1"

$siteCode = $(Get-WMIObject -ComputerName "$env:ComputerName" -Namespace "root\sms" -class "SMS_ProviderLocation" -ErrorAction SilentlyContinue).SiteCode 

If (!($siteCode))
{
   # $siteCode = $([WmiClass]"\\localhost\ROOT\ccm:SMS_Client").GetAssignedSite()
    $siteCode = (Get-ItemProperty -Path "HKLM:SOFTWARE\Microsoft\SMS\Mobile Client").AssignedSiteCode
}

Set-Location "$($siteCode):"

$getOUs = (Get-CMResource -ResourceType System -fast).SystemOUName | Select-Object -Unique

ForEach ($ou in $getOUs)
{
    New-CMQuery -Name $ou -TargetClassName 'SMS_R_SYSTEM' -Expression "select SMS_R_System.Name from SMS_R_System where SMS_R_System.SystemOUName = '$ou'" -Comment "Created by PowerShell" | Move-CMObject -FolderPath "$($siteCode):\Query\OU Queries"
}
