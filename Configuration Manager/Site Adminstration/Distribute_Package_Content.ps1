Import-Module "$env:SMS_ADMIN_UI_PATH\..\configurationmanager.psd1"

$siteCode = $(Get-WMIObject -ComputerName "$ENV:ComputerName" -NameSpace "root\sms" -Class "SMS_ProviderLocation").SiteCode

Set-Location "$($siteCode):"

$dpList = @()
$dpList += "Server1-FQDN"
$dpList += "Server2-FQDN"

$contentType = "Package"

$contentIDs = @()
$contentIDs += "ABC123456"

ForEach ($id IN $contentIDS)
{
    ForEach ($dp IN $dpList)
    {
        IF ($contentType -eq "Package")
        {
            Start-CMContentDistribution -PackageID $id -DistributionPointName $dp
        }
        ElseIF ($contentType -eq "BootImage")
        {
            Start-CMContentDistribution -BootImageID $id -DistributionPointName $dp
        }
        ElseIF ($contentType -eq "Task Sequence")
        {
            Start-CMContentDistribution -TaskSequenceID $id -DistributionPointName $dp
        }
        ElseIF ($contentType -eq "Operating System")
        {
            Start-CMContentDistribution -OperatingSystemImageID $id -DistributionPointName $dp
        }
        ElseIF ($contentType -eq "Software Update Package")
        {
            Start-CMContentDistribution -DeploymentPackageName "$($id)" -DistributionPointName $dp
        }
        ElseIF ($contentType -eq "Application")
        {
            Start-CMContentDistribution -ApplicationName "$($id)" -DistributionPointName $dp
        }
        ElseIF ($contentType -eq "Driver Package")
        {
            Start-CMContentDistribution -DriverPackageName "$($id)" -DistributionPointName $dp
        }  
    }
}

Set-Location C:



