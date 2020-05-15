$getSub = Get-AzureRMSubscription | Where-Object name -eq "Mirosoft Azure Internal Consumption"
Add-AzureRmAccount -SubscriptionID $getSub.Id
