
Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\Console\bin\ConfigurationManager.psd1"

$arrCollections = Get-Content $PSScriptRoot\CollectionNames.txt

$SCCMSiteCode = "MySiteCode"
$CMSitePath = $SCCMSiteCode+ ":"

$strLimitingCollection = "Limiting Collection Name"

Set-Location $CMSitePath

$strRefreshSchedule = New-CMSchedule -RecurInterval Hours -RecurCount 4
ForEach ($collection in $arrCollections)
{
    $strCollectionName = $collection
    If (Get-CMDeviceCollection -Name "$strCollectionName")
    {
        Write-Host "Collection $strCollectionName already exists!"
    }
    Else
    {
        $strMembershipQuery = "select *  from  SMS_R_System where SMS_R_System.Name like 'PC-%'"
        Try
        {
            New-CMDeviceCollection -Name $strCollectionName -LimitingCollectionName $strLimitingCollection -RefreshSchedule $strRefreshSchedule -RefreshType Periodic
            Add-CMDeviceCollectionQueryMembershipRule -CollectionName $strCollectionName -QueryExpression $strMembershipQuery -RuleName "Computer name like PC-*"
            
        }
        Catch
        {    
            Write-Host "Creation of collection $strCollectionName failed: $error[0]"
        }
    }  
}

Set-Location C: