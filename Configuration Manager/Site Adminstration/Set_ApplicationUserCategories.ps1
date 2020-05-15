Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\Console\bin\ConfigurationManager.psd1"

$SCCMSiteCode = "MySiteCode"
$CMSitePath = $SCCMSiteCode+ ":"

Set-Location $CMSitePath

$appName = "Adobe Air"

$userCategory = "Productivity"

try {
    Get-CMApplication -Name $appName
}
catch {
    Write-Host "ERROR: " + $Error[0]
    Exit $LASTEXITCODE
}


$getCategory = Get-CMCategory -CategoryType CatalogCategories -Name $userCategory

try {
    If (!($getCategory))
    {
        New-CMCategory -CategoryTyoe CatalogCategories -Name $userCategory
    }
    
    Set-CMApplication -Name $appName -UserCategory $userCategory
}
catch
{
    Write-Host $error[0]
}
Finally
{
    Exit $LASTEXITCODE
}


