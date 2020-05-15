Connect-AzAccount

$getSub = Get-AzureRMSubscription | Where-Object name -eq "My Subscription"
Add-AzureRmAccount -SubscriptionID $getSub.Id

$azResource = Get-AzureRMResource -name "VMName" -ResourceGroupName "MY_LAB"

$resTags = $azResource.tags

$resTags += @{CMSiteCode="CM1"; CMParentSiteCode="CAS"}

Set-AzureRMResource -ResourceID $azResrouce.ID -Tag $resTags -Force

# Get all resources with the desired tag
Get-AzureRMResource -TagName CMSiteCode

# Get all resource names with a tag matching the desired values
(Get-AzureRMResource -TagName @{CMSiteCode="CM1"}).Name