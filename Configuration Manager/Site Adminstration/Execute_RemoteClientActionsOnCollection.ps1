Clear-Host

Start-Transcript -Path "$PSScriptRoot\RemoteClientActionsOnCollection.log" -Force

try {
    Import-Module "$env:SMS_ADMIN_UI_PATH\..\configurationmanager.psd1" -ErrorAction Stop
}
catch {
    "ERROR: Unable to import ConfigMgr PowerShell module."
    EXIT
}

$mySiteCode = "CM1:"

Set-Location $mySiteCode

$mySite = get-cmsite

If (!$mySite)
{
    Write-Host "Error connecting to Configuration Manager Site"
    Write-Host $Error[0]
    Stop-Transcript
    Exit
}

$collectionName = Read-Host "Enter collection name to target"
$collectionInfo = Get-CMDeviceCollection -Name $collectionName

If (!$collectionInfo)
{
    Write-Host "Error: Collection ($collectionName) not found. Exiting."
    Stop-Transcript
    Exit
}
Else
{
    Write-Host "Collection $collectionName found. Attempting to get members."
    $collectionMembers = Get-CMCollectionMember -CollectionName $collectionName
    If (!$collectionMembers -or $collectionMembers.count -lt 1)
    {
        Write-Host "WARNING: Collecton contains no members or error retrieving members. Exiting."
        Stop-Transcript
        EXIT
    }
}
Write-Host ""
Write-Host "Confirming colleciton information."
Write-Host "Name: "$collectionInfo.Name
Write-Host "ID: "$collectionInfo.CollectionID 
Write-Host "Member count: "$collectionMembers.count
Write-Host ""
Write-Host "Do you want to continue?"
Write-Host ""
$continueYN = Read-Host "(Y/N)"

If ($continueYN -eq "y")
{
    Clear-Host
}
ElseIf($continueYN -eq "n")
{
    Write-Host "Exiting."
    Stop-Transcript
    Exit
}
else
{
    Write-Host "Unrecognized input. Exiting."
    Stop-Transcript
    Exit 1603    
}

Write-Host "Choose the client action to initiate"
Write-Host "1 - Machine Policy Retreival Cycle"
Write-Host "2 - Machine Policy Evaluation Cycle"
Write-Host "3 - Hardware Inventory Cycle"
Write-Host "4 - Software Update Scan Cycle"
Write-Host "5 - Software Update Deployment Evaluation Cycle"
Write-Host "6 - Software Inventory Cycle"
Write-Host "7 - App Deployment Evaluation Cycle"
Write-Host "8 - Compliance Evaluation Cycle"
Write-Host "9 - Discovery Data Collection Cycle"
$clientActionChoice = Read-Host "Selection" 

If ($clientActionChoice -eq "1")
{
    $clientActionName = "Machine Policy Retreival Cycle"
    $clientAction = "{00000000-0000-0000-0000-000000000021}"
}
ElseIf ($clientActionChoice -eq "2")
{
    $clientActionName = "Machine Policy Evaluation Cycle"
    $clientAction = "{00000000-0000-0000-0000-000000000022}"
}
ElseIf ($clientActionChoice -eq "3")
{
    $clientActionName = "Hardware Inventory Cycle"
    $clientAction = "{00000000-0000-0000-0000-000000000001}"
}
elseif ($clientActionChoice -eq "4") 
{
    $clientActionName = "Software Update Scan Cycle"
    $clientAction = "{00000000-0000-0000-0000-000000000113}"
}
elseif ($clientActionChoice -eq "5") 
{
    $clientActionName = "Software Update Deployment Evaluation Cycle"
    $clientAction = "{00000000-0000-0000-0000-000000000108}"
}
elseif ($clientActionChoice -eq "6") 
{
    $clientActionName = "Software Inventory Cycle"
    $clientAction = "{00000000-0000-0000-0000-000000000002}"
}
elseif ($clientActionChoice -eq "7") 
{
    $clientActionName = "App Deployment Evaluation Cycle"
    $clientAction = "{00000000-0000-0000-0000-000000000121}"
}
elseif ($clientActionChoice -eq "8") 
{
    $clientActionName = "Compliance Evaluation Cycle"
    $clientAction = "{00000000-0000-0000-0000-000000000071}"
}
elseif ($clientActionChoice -eq "9") 
{
    $clientActionName = "Discovery Data Collection Cycle"
    $clientAction = "{00000000-0000-0000-0000-000000000003}"
}
else
{
    Wite-Host "Unrecognized input. Exiting."
    Exit 1603
}

Clear-Host
Write-Host "Preparing to initiate client action on collection members"
Write-Host "Collection: "$collectionInfo.Name "("$collectionInfo.CollectionID")"
Write-Host "Collection Members: "$collectionMembers.count
Write-Host "Client Action: $clientActionName $clientAction"
Write-Host ""
Write-Host "Press ENTER to begin action or type 'exit' to stop:"
$continueExit = Read-Host

If ($continueExit -eq "exit")
{
    Stop-Transcript
    Exit
}
else {
    Clear-Host
}

foreach ($_ in $collectionMembers)
{
    $error.clear()    
    $deviceName = $_.name
    Write-Host -NoNewLine "$deviceName "
    Invoke-WMIMethod -ComputerName $deviceName -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule $clientAction -ErrorAction SilentlyContinue | Out-Null
    If ($error[0])
    {
        Write-Host ":"$error[0]
    }
    Else
    {
        Write-Host ": Success"
    }
    
}

Write-Host "Execution complete."

Stop-Transcript

Set-Location C: