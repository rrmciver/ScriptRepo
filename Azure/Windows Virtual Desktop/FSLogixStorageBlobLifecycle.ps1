<#
.SYNOPSIS
    Generates a list of stale page blobs used for FSLogix CloudCache user profile containers and optionally performs a cleanup
.DESCRIPTION
    This script is intended to be used via an Azure Function with a System Assigned identity and executed on a recurring schedule.
    The provided storage account will be queried and page blobs found exceeding the lifecycle age will be reported on and, optionally, deleted.
.NOTES
    Script is offered as-is with no warranty, expressed or implied.
    Author: Richard McIver
    Last Modified: 8/28/2020

    The storage account identity must have the Contributor IAM role on the target storage account.

    If the Storage Account Firewall is enabled and the Function App running this script is in the same region, Microsoft internal IP addresses and routing will be used to make the calls.
    Therefore, it is recommended to create the Function App in a seperate region to force the use a limited pool of external IP addresses. This IPs can then be added as excpetions on the storage account firewall.
    To view the pool of external IPs for the Fucntion App, log into Azure Resource Explorer (http://resources.azure.com) and browse to Subscriptions -> MyWVDSubscription -> Providers -> Microsoft.Web -> Sites.
    Scroll down through the code until you find the ID for the appropriate Function App, then look for the possibleOutboundIpAddresses attribute. 
    
    The reporting feature of this script relied on a Power Automate Flow to accept an HTTP request containing the message sendto, subject, and email body and then send the email.
#>

# Input bindings are passed in via param block.
param($Timer)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

Function RemoveStaleBlobs($blobs){
    $deleteCount = 0
    ForEach($blob in $blobs){
        Try{
            #"Removing blob: $($blob.Name)"
            $blob | Remove-AzStorageBlob -Force
            $deleteCount++
        }
       Catch{
            Write-Error "StorageAccount: $($stgAcctName); BlobName: $($blob.Name); $_"
            Break
        }
    }
    Write-Host "StorageAccount: $($stgAcctName); StaleBlobsDeleted: $deleteCount"
    return $deleteCount
}

# Dev blob storage acct
$stgResGroup = "MyStorageAccountResourceGroup"
$stgAcctName = "MyStorageAccountName"

# Specify a container prefix to limit the search scope
$containerPrefix = "prod"
# Set the the last modified date threashold in days for considering blobs to be stale
$staleBlobAge = "3"

# Should we send an email report when stale blobs are found?
# If yes, will send a request to MSFT Power Automate to trigger sending of the email
$sendReportEmail = "yes"
$msftFlowUrl = "MyFlowURL"
$emailSubject = "WVD Stale User Profile Blobs Report"
$emailAddress = "MyDistributionList@email.com"

# Should we attempt to delete stale blobs after finding them?
$deleteStaleBlobs = "yes"

# Initialize other variables
$utcDate = ((get-date).ToUniversalTime())
$staleBlobList = @()
$staleBlobSize = 0
$deletedBlobsCount = 0

# Get list of stale blobs from storage account
Try{
    $staleBlobs = Get-AzStorageAccount -ResourceGroupName $stgResGroup -Name $stgAcctName | Get-AzStorageContainer -Prefix $containerPrefix | Get-AzStorageBlob | Where-Object LastModified -lt $utcDate.AddDays(-$staleBlobAge)
    # Parse the relevant information for reporting and calculate the combined size of stale blobs in the storage account
    ForEach($blob in $staleBlobs){
        $staleBlobSize = $staleBlobSize + $blob.Length 
        $containerName = ($blob.ICloudBlob.uri.AbsoluteUri).split("/")[-2]
        $objItem = New-Object PSObject
        $objItem | Add-Member -type NoteProperty -Name 'Container' -Value "$containerName"
        $objItem | Add-Member -type NoteProperty -Name 'BlobName' -Value "$($blob.Name)"
        $objItem | Add-Member -type NoteProperty -Name 'BlobSize' -Value "$($blob.Length / 1MB)"
        $objItem | Add-Member -type NoteProperty -Name 'LastModified' -Value "$($blob.LastModified)"
        $staleBlobList += $objItem
    }
    # Write-Host "StorageAccount: $($stgAcctName); StaleBlobsFound: $($staleBlobs.Count)"
}
Catch{
    Write-Error "StorageAccount: $($stgAcctName); $_"
    Exit
}

# Convert the calculated total size to the appropriate units
If (($staleBlobSize / 1GB) -ge 1){
    $staleBlobSize = $staleBlobSize / 1GB
    $sizeLabel = "GB"
}
ElseIf (($staleBlobSize / 1MB) -ge 1){
    $staleBlobSize = $staleBlobSize / 1MB
    $sizeLabel = "MB"
}
ElseIf (($staleBlobSize / 1KB) -ge 1){
    $staleBlobSize = $staleBlobSize / 1KB
    $sizeLabel = "KB"
}

Write-Host "StorageAccount: $($stgAcctName); StaleBlobsFound: $($staleBlobs.Count); StaleBlobsSize: $staleBlobSize $sizeLabel"

If($deleteStaleBlobs -eq "yes"){
    $deletedBlobsCount = RemoveStaleBlobs $staleBlobs
} 

If ($staleBlobs.count -gt 0 -and $sendReportEmail -eq "yes"){
    $emailBody = ""
    $emailBody += "<h4>Storage Account: $stgAcctName </h4>"
    $emailBody += "<b>Container, Blob, Size (MB), LastModified (UTC)</b><br/>"
    ForEach($obj in $staleBlobList){
        $emailBody += "$($obj.Container), $($obj.BlobName), $($obj.BlobSize), $($obj.LastModified)<br/>"
    }
    #$staleBlobList | %{ $emailBody += "$_<br/>"}
    $emailBody += "<br/><br/>"

    $emailBody = "<h1>Stale FSLogix page blobs were detected in the Azure storage account $stgAcctName.</h1> <br/>This message is the result of a periodic maintenance check of FSLogix user profile blobs used with the Windows Virtual Desktop (ARM) production host pools. To reduce storage costs, aged user profiles should be routinely deleted.</a><br/>" + `
    "<br/><br/><h4>Total number of profile blobs older than $staleBlobAge days: $($staleBlobs.count) <br/><br/> Total size of stale blobs: $staleBlobSize $sizeLabel <br/><br/> Numer of stale blobs deleted: $deletedBlobsCount</h4><br/><br/> <h4>Stale Blobs List</h4>" + $emailBody + "<br/><br/><br/><br/><br/>"

    $JobUriParameters = New-Object PSObject -Property @{
        'emailAddress' = $emailAddress;
        'emailSubject' = $emailSubject;
        'emailBody' = $emailBody
    }

    $MSFlowParam = ConvertTo-Json -InputObject $JobUriParameters
    Invoke-WebRequest -Uri $msftFlowUrl -ContentType "application/json" -Method POST -Body $MSFlowParam -UseBasicParsing
}