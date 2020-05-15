
Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\Console\bin\ConfigurationManager.psd1"

$arrColNames = Get-Content $PSScriptRoot\CollectionNames.txt

$SCCMSiteCode = "MySiteCode"
$CMSitePath = $SCCMSiteCode+ ":"

$strExcludeCollectionNam = "Exclusions"

Set-Location $CMSitePath

ForEach ($collection in $arrColNames)
{
    $strCollectionName = $collection
    If (Get-CMDeviceCollection -Name "$strCollectionName")
    {
        Try
        {
            Add-CMDeviceCollectionExcludeMembershipRule -CollectionName $strCollectionName -ExcludeCollectionName $strExcludeCollection
        }
        Catch
        {
            Write-Host "Adding exclusion collection failed: $error[0]"
        }
    }
    Else
    {
        Write-Host "Collection not found"
    }  
}

Set-Location C: