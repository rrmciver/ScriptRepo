Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\Console\bin\ConfigurationManager.psd1"

$SCCMSiteCode = "MYSiteCode"
$CMSitePath = $SCCMSiteCode+ ":"

Set-Location $CMSitePath

$getApps = Get-CMApplication | Where-Object LocalizedDisplayName -like "*"
ForEach ($_ in $getApps)
{
    $appName = $_.LocalizedDisplayName
    Write-Host "Found CM Application: $appName"
    $getDeploymentTypes = Get-CMDeploymentType -ApplicationName $appName
    ForEach ($_ in $getDeploymentTypes)
    {
        $deptTypeName = $_.LocalizedDisplayName
        Write-Host "Updating content for Deployment Type: $deptTypeName"
        Update-CMDistributionPoint -ApplicationName $appName -DeploymentTypeName $deptTypeName
    }
}