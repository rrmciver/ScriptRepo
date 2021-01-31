<#
    Description: This script automates the process for capturing a managed image from an Azure VM without destroying the source template vm. It is intended for execution via an Azure Automation runbook with appropriate permissions to the WVD subscription.

    Use: 
        Prompts for several required parameters will appear when executing the runbook:

        -[string]TemplateVMName: The name of the Azure VM to be captured
        -[string]TemplateVMResurceGroupName: The name of the resource group containing the Azure VM
        -[string]ImageName: The name of the image that will be created (Note that a timestamp will be automatically appended to provided name to ensure it is unique)
        -[strng]ImageResourceGroupName: The resouece group name where the image will be created

        In addition, several global Automation Account variables are required:

        -[string]ScriptStorageAccountName: Name of the storage account containing the os generalization script and supporting files
        -[string]ScriptStorageAccountResourceGroupName: Name of the resource group containing the storage account
        -[string]ScriptContainerName: Name of the blob container on the storage account containing the generalization script and files
        -[string]GeneralizeScriptFileName: Full file name (including extension) of the os generalization script
        -[bool]CallCleanup: If set to True, will automatically run cleanup actions to delete temporary resources creating during execution
        -[bool]CallCleanupOnError: If set to True, will attempt to run cleanup actions if an error is encountrered during the process

    Summary: 
        When executed, this runbook will perform the following high-level actions:

        - Stop and deallocate the template virtual machine
        - Create a temporary snapsht of the template vm os disk
        - Create a temporary os disk from the the snapshot
        - Create a temporary network interface based on the template vm configuration
        - Create a temporary virtual machine, attaching the temp os disk and nic
        - Execute the os generalization script via the CustomScriptExtension on the temporary vm
        - Create a managed image from the generalized temp vm
        - Delete the temp vm, temp os disk, temp nic, and temp snpashot
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$templateVMName,

    [Parameter(Mandatory=$true)]
    [string]$templateVMResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$imageName,
    
    [Parameter(Mandatory=$true)]
    [string]$imageResourceGroupName
)

Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false

# Setting ErrorActionPreference to stop script execution when error occurs
$ErrorActionPreference = "Stop"
$VerbosePreference = "SilentlyContinue"

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave –Scope Process | Out-Null

$connection = Get-AutomationConnection -Name AzureRunAsConnection

# Wrap authentication in retry logic for transient network failures
$logonAttempt = 0
while(!($connectionResult) -and ($logonAttempt -le 10))
{
    $LogonAttempt++
    # Logging in to Azure...
    $connectionResult = Connect-AzAccount `
                            -ServicePrincipal `
                            -Tenant $connection.TenantID `
                            -ApplicationId $connection.ApplicationID `
                            -CertificateThumbprint $connection.CertificateThumbprint

    Start-Sleep -Seconds 30
}

# Set Azure context to the automation account subscription
$AzureContext = Get-AzSubscription -SubscriptionId $connection.SubscriptionID | Select-AzSubscription

if(!($AzureContext)){
    Write-Output "Please provide a valid subscription"
    exit
} 
else{
    $AzSubObj = $AzureContext | Out-String
    Write-Output "Sets the Azure subscription. Result: `n$AzSubObj"
}

# Runbook functions

Function GetAzureVMState($vmName, $rgName){
    try{
        $vmStatuses = (Get-AZVM -ResourceGroupName $rgName -Name $vmName -Status).Statuses
        ForEach($status in $vmStatuses){
            if($status.Code -like "PowerState*"){
                $vmState = $status.DisplayStatus
            }
        }
        
    }catch{
        $vmState = "Error: $($PSItem.Exception.Message)"
    }
    
    return $vmState
}

Function StopVirtualMachine($vmName, $rgName){
    $funcOutput = ""
    Try{
        Stop-AzVM -ResourceGroupName $rgName -Name $vmName -Force | Out-Null
        $funcOutput = "VM stopped successfully: $vmName"
    }Catch{
        $funcOutput = "Error: $($PSItem.Exception.Message)"
    }

    return $funcOutput
}

Function StartVirtualMachine($vmName, $rgName){
    $funcOutput = ""
    Try{
        Start-AzVM -ResourceGroupName $rgName -Name $vmName | Out-Null
        $funcOutput = "VM started successfully: $vmName"
    }Catch{
        $funcOutput = "Error: $($PSItem.Exception.Message)"
    }

    return $funcOutput
}

Function CreateDiskSnapshot([object]$sourcevm, [string]$timeStamp){
    # Establish snapshot name
    $name = ($sourcevm.Name).ToLower()
    $snapshotName = "snap_temp_$($name)_osdisk_$timeStamp"
    $skuName = "Standard_LRS"

    $sourceUri = $sourcevm.StorageProfile.OsDisk.ManagedDisk.Id
    $location = $sourcevm.Location
    $sourcerg = $sourcevm.ResourceGroupName

    # Create the snapshot
    Try{
        # Create the snapshot
        $snapshotConfig = New-AzSnapshotConfig -SourceUri $sourceUri -Location $location -CreateOption Copy -SkuName $skuName
        $snap = New-AzSnapshot -Snapshot $snapshotConfig -SnapshotName $snapshotName -ResourceGroupName $sourcerg
        #$snap = Get-AzSnapshot -ResourceGroupName $sourcerg -SnapshotName "snap_temp_oitwvddevumd02_osdisk_202010301333"
    }
    catch{
        $snap = "Error: $($PSItem.Exception.Message)"
    }

    return $snap
}

Function CreateTempOSDisk([object]$snapshot, [string]$vmName, [object]$sourceVM){
    # Establish os disk name and parameters
    $osDiskName = "$($vmName)_os_disk"
    $snapId = $snapshot.Id
    $skuName = "Standard_LRS"
    $rgName = $sourceVM.ResourceGroupName
    $location = $sourceVM.location

    try{
        # Create temporary os disk config
        $tempDiskConfig = New-AzDiskConfig -SkuName $skuName -Location $location -CreateOption Copy -SourceResourceId $snapId 
        # Create temporary os disk
        $tempDisk = New-AzDisk -Disk $tempDiskConfig -ResourceGroupName $rgName -DiskName $osDiskName
        
        #$tempDisk = Get-AzDisk -ResourceGroupName $rgName -DiskName "temp_oitwvddevumd02_202010301333_os_disk"
    }
    catch{
        $tempDisk = "Error: $($PSItem.Exception.Message)"
    }

    return $tempDisk
}

Function CreateTempNIC([string]$sourceSubnetId, [string]$vmName, [object]$sourceVM){
    # Establish temp nic name and set params
    $tempNICName = "$($vmName)_nic"
    $rgName = $sourceVM.ResourceGroupName
    $location = $sourceVM.location

    try{
        # Create temp nic
        $tempNic = New-AzNetworkInterface -Name $tempNICName -ResourceGroupName $rgName -Location $location -SubnetId $sourceSubnetId
        #$tempNic = Get-AzNetworkInterface -ResourceGroupName $rgName -Name "temp_oitwvddevumd02_202010301333_nic"
    }
    catch{
        $tempNic = "Error: $($PSItem.Exception.Message)"
    }

    return $tempNic
}

Function CreateTempVM([string]$vmName, [string]$vmSize, [object]$osDisk, [object]$nic, [object]$sourceVM){
    # Establish params
    $createSuccess = $true
    $diskID = $osDisk.Id
    $nicID = $nic.Id
    $rgName = $sourceVM.ResourceGroupName
    $location = $sourceVM.Location
    
    # Create temp vm from temp os disk and nic
    try{    
        $tempVM = New-AzVMConfig -VMName $vmName -VMSize $vmSize
        $tempVM = Set-AzVMOSDisk -VM $tempVM -ManagedDiskId $diskID -CreateOption Attach -Windows
        $tempVM = Add-AzVMNetworkInterface -VM $tempVM -Id $nicID
        $tempVM = Set-AzVMBootDiagnostic -vm $tempVM -Disable
        $tempVM = New-AzVM -VM $tempVM -ResourceGroupName $rgName -Location $location -DisableBginfoExtension
        
        if($tempVm.IsSuccessStatusCode -eq "True"){
            $createSuccess = $true
        }
        else{
            throw "New-AzVM returned non-success status code"
        }
    }
    catch{
        $getTempVM = "Error: $($PSItem.Exception.Message)" 
    }

    if($createSuccess){
        try{
            $getTempVM = Get-AzVM -ResourceGroupName $rgName -Name $vmName
            #$getTempVM = Get-AzVM -ResourceGroupName $rgName -Name "temp_oitwvddevumd02_202010301333"
        }
        catch{
            $getTempVM = "Error: $($PSItem.Exception.Message)"
        }
        
    }

    return $getTempVM
}

Function CaptureVirtualMachineImage($tempVM, $imgName, $imgRG, $timeStamp){
    # Establish image name and set params
    $imgName = "$($imgName)-$timeStamp"
    $location = $tempVM.Location
    $sourceVmId = $tempVM.Id

    # Create the managed image
    try{
        $imageConfig = New-AzImageConfig -Location $location -SourceVirtualMachineId $sourceVmId
        $manImage = New-AzImage -Image $imageConfig -ImageName $imgName -ResourceGroupName $imgRG
    }
    catch{
        $manImage = "Error: $($PSItem.Exception.Message)"
    }

    return $manImage
}

Function CleanupTempResources(){
    param(
        [Parameter(Mandatory=$false)]
        [object]$tempVirtualMachine,

        [Parameter(Mandatory=$false)]
        [object]$tempDisk,

        [Parameter(Mandatory=$false)]
        [object]$tempNetworkInterface,
        
        [Parameter(Mandatory=$false)]
        [object]$tempSnapshot
    )

    $returnVal = @()

    if($tempVirtualMachine){
        try{
            $vmStatus = (Get-AzVM -ResourceGroupName $tempVirtualMachine.ResourceGroupName -Name $tempVirtualMachine.Name -Status).Statuses
            ForEach($status in $vmStatus){
                if($status.Code -like "PowerState*"){
                    $vmState = $status.DisplayStatus
                }
            }

            if($vmState -like "*running*"){
                Stop-AzVM -ResourceGroupName $tempVirtualMachine.ResourceGroupName -Name $tempVirtualMachine.Name -Force | Out-Null
            }
            elseif(!($vmState)){
                throw "Error: Unable to get temp vm power state"
            }
            else{
                # Continue
            }

            Remove-AzVM -ResourceGroupName $tempVirtualMachine.ResourceGroupName -Name $tempVirtualMachine.Name -Force | Out-Null
            Start-Sleep -s 300
            $returnVal += "Temporary vm cleanup complete"
        }
        catch{
            return $PSItem.Exception.Message
        }
    }

    if($tempDisk){
        Try{
            # Verify OS disk exists and is not currently attached to a vm. If true, then delete the disk
            $getTempDisk = Get-AzDisk -ResourceGroupName $tempDisk.ResourceGroupName -DiskName $tempDisk.Name
            if($getTempDisk.ManagedBy){
                throw "WARN: Temporary disk is attached to a vm. Disk will not be deleted. Attached VM: $($getTempDisk.ManagedBy)"
            }
            elseif($getTempDisk){
                Remove-AzDisk -ResourceGroupName $tempDisk.ResourceGroupName -DiskName $tempDisk.Name -Force | Out-Null
                Start-Sleep -s 120
                $returnVal += "Temporary disk cleanup complete"
            }
            else{
                throw "ERROR: Temporary disk not found"
            }
        }
        catch{
            $returnVal += $PSItem.Exception.Message
        }
    }
   
   if($tempNetworkInterface){
       try{
           # Verify Nic is not attached to a vm
            $getTempNic = Get-AzNetworkInterface -ResourceGroupName $tempNetworkInterface.ResourceGroupName -Name $tempNetworkInterface.Name
            if($getTempNic.VirtualMachine){
                throw "WARN: Temporary nic is attached to a vm. Nic will not be deleted. Attached to VM: $($getTempNic.VirtualMachine)"
            }
            elseif($getTempNic){
                Remove-AzNetworkInterface -ResourceGroupName $tempNetworkInterface.ResourceGroupName -Name $tempNetworkInterface.Name -Force | Out-Null
                Start-Sleep -s 120
                $returnVal += "Temporary nic cleanup complete"
            }
            else{
                throw "ERROR: Temporary nic not found"
            }
        }
        catch{
            $returnVal += $PSItem.Exception.Message
        }
   }

   if($tempSnapshot){
       try{
            # Verify snapshot is not attached to a vm
            $getSnapshot = Get-AzSnapshot -ResourceGroupName $tempSnapshot.ResourceGroupName -SnapshotName $tempSnapshot.Name
            if($getSnapshot.ManagedBy){
                throw "WARN: Temporary snapshot has an active attachment. Snapshot will not be deleted. Attachment: $($getSnapshot.ManagedBy)"
            }
            elseif($getSnapshot){
                Remove-AzSnapshot -ResourceGroupName $tempSnapshot.ResourceGroupName -SnapshotName $tempSnapshot.Name -Force | Out-Null
                $returnVal += "Temporary snapshot cleanup complete"
            }
            else{
                throw "Error: snapshot not found"
            }
        }
        catch{
            $returnVal += $PSItem.Exception.Message
        }
   }
 
    return $returnVal
}

# Write runbook variables to stream for verification and debugging
Write-Output ""
Write-Verbose "Using values passed as paramaters during script execution..."
Write-Output "Template virtual machine name: $templateVMName"
Write-Output "Template vm resource group name: $templateVMResourceGroupName"
Write-Output "Image name: $imageName"
Write-Output "Image resource group: $imageResourceGroupName"
Write-Output ""

# Get global variables from the automation account and write thier values to the stream
Write-Verbose "Getting variables from automation account..."
$scriptStorageAccountName = (Get-AutomationVariable -Name 'ScriptStorageAccountName')
$scriptStorageAccountRG = (Get-AutomationVariable -Name 'ScriptStorageAccountResourceGroupName')
$scriptContainerName = (Get-AutomationVariable -Name 'ScriptContainerName')
$genScriptFileName = (Get-AutomationVariable -Name 'GeneralizeScriptFileName')
$runCleanup = (Get-AutomationVariable -Name 'CallCleanup')
$cleanupOnError = (Get-AutomationVariable -Name 'CallCleanupOnError')

Write-Output "Script storage account name: $scriptStorageAccountName"
Write-Output "Script storage account resource group name: $scriptStorageAccountRG"
Write-Output "Script container name: $scriptContainerName"
Write-Output "Generalization script file name: $genScriptFileName"
Write-Output "Call cleanup module: $runCleanup"
Write-Output "Cleanup on error: $cleanupOnError"
Write-Output ""

# Begin main 

# Get timestamp for resource name generation
$getTimeStamp = Get-Date -Format "yyyyMMddHHmm"
Write-Output "Current timestamp: $getTimeStamp"

# Set files to copy from storage account during generalizaton
$containerFiles = @("ITPC-WVD-Image-Processing.ps1","Microsoft.RDInfra.RDAgent.msi","Microsoft.RDInfra.RDAgentBootLoader.msi")
$containerFiles += "$genScriptFileName"

# Get tempalte vm object and status
Write-Output "Getting souce virtual machine details.."
try{
    $objSourceVM =  Get-AZVM -ResourceGroupName $templateVMResourceGroupName -Name $templateVMName
    $sourceNicId = ($objSourceVM.NetworkProfile.NetworkInterfaces).Id
    $sourceNic = Get-AzNetworkInterface -ResourceId $sourceNicId
    $sourceSubnetId = $sourceNic.IpConfigurations[0].subnet.Id
    $sourceVMSize = $objSourceVM.HardwareProfile.VmSize
    Write-Output "Successfully retreived template vm information"
    Write-Output "Template VM ID: $($objSourceVM.Id)"
    Write-Output "Template VM Subnet ID: $sourceSubnetId"
    Write-Output "Template VM Size: $sourceVMSize"
    Write-Output ""
}catch{
    #Write-Error "Error getting vm details; Name: $templateVMName; RG: $templateVMResourceGroupName"
    Write-Error $PSItem.Exception.Message
    exit
}

# Get template vm status
Write-Output "Getting source vm status.."
$sourceVMState = GetAzureVMState $templateVMName $templateVMResourceGroupName 
If($sourceVMState -like "Error:*"){
    Write-Error $sourceVMState
    exit
}
else{
    Write-Output "Source vm status is: $sourceVMState"
}

# Verify template vm is stopped and deallocated
If($sourceVMState -like "*running*"){
    Write-Output "Stopping and deallocating source vm..."
    $stopVM = StopVirtualMachine $templateVMName $templateVMResourceGroupName
    If($stopVM -like "Error:*"){
        Write-Error $stopVM
        exit
    }
    Else{
        Write-Output $stopVM
    }
}

# Establish name for the temporary vm
$tempVMName = ("temp_$($objSourceVM.Name)_$getTimeStamp").ToLower()
Write-Output "Temporary VM name will be: $tempVMName"

# Create a snapshot of the OS Disk
Write-Output "Creating os disk snapshot from source template vm..."
$osDiskSnapshot = CreateDiskSnapshot $objSourceVM $getTimeStamp
if($osDiskSnapshot -like "Error:*"){
    Write-Error $osDiskSnapshot
    exit
}
else{
    Write-Output "Temporary snapshot successfully created: $($osDiskSnapshot.Name)" 
}

# Create a temp os disk from the snapshot
Write-Output "Creating temporary os disk from snapshot..."
$temporaryOSDisk = CreateTempOSDisk $osDiskSnapshot $tempVMName $objSourceVM
if($temporaryOSDisk -like "Error:*"){
    Write-Error $temporaryOSDisk
    if($cleanupOnError){
       #Cleanup temp snapshot
       Write-Output "Performing cleanup after error event..."
        $cleanup = CleanupTempResources -tempSnapshot $osDiskSnapshot
        Write-Output $cleanup
    }
    exit
}
else{
    Write-Output "Temporary os disk created: $($temporaryOSDisk.Name)"
}

# Create temp nic for the tempvm
Write-Output "Creating temporary network interface..."
$temporaryNic = CreateTempNIC $sourceSubnetId $tempVMName $objSourceVM
if($temporaryNic -like "Error:*"){
    Write-Error $temporaryNic
    if($cleanupOnError){
       #Cleanup temp snapshot and temp os disk
       Write-Output "Performing cleanup after error event..."
        $cleanup = CleanupTempResources -tempDisk $temporaryOSDisk -tempSnapshot $osDiskSnapshot
        Write-Output $cleanup
    }
    exit
}
else{
    Write-Output "Temporary network interface created: $($temporaryNic.Name)"
}

# Create temp vm 
Write-Output "Creating temporary virtual machine for generalization..."
$temporaryVm = CreateTempVM $tempVMName $sourceVMSize $temporaryOSDisk $temporaryNic $objSourceVM
if($temporaryVm -like "Error:*"){
    Write-Error $temporaryVm
    if($cleanupOnError){
       #Cleanup temp snapshot, os disk, and nic
       Write-Output "Performing cleanup after error event..."
        $cleanup = CleanupTempResources -tempNetworkInterface $temporaryNic -tempDisk $temporaryOSDisk -tempSnapshot $osDiskSnapshot
        Write-Output $cleanup
    }
    exit
}
else{
    Write-Output "Temporary virtual machine created: $($temporaryVm.Name)"
}

# Generalize temp vm
Write-Output "Generalizing temp vm OS and preparing it for image capture..."

# Verify vm is not already generalized (primarily for debugging scenarios)
try{
    $isGeneralized = $false
    $tempVMStatuses = (Get-AzVm -ResourceGroupName $temporaryVM.ResourceGroupName -Name $temporaryVm.Name -Status).Statuses
    ForEach($status in $tempVMStatuses){
        if($status.Code -eq "OSState/generalized" -and $status.DisplayStatus -eq "VM generalized"){
            $isGeneralized = $true
        }
    }
}
catch{
    Write-Error $PSItem.Exception.Message
    if($cleanupOnError){
        Write-Output "Performing cleanup after error event..."
        $cleanup = CleanupTempResources -tempVirtualMachine $temporaryVm -tempNetworkInterface $temporaryNic -tempDisk $temporaryOSDisk -tempSnapshot $osDiskSnapshot
        Write-Output $cleanup
    }
    exit
}

# Verify temporary VM is started and available
if(!($isGeneralized)){
    Write-Output "Verifying temp vm is running..."
    $tempVMState = GetAzureVMState $temporaryVM.Name $temporaryVM.ResourceGroupName
    if($tempVMState -like "Error:*"){
        Write-Error $tempVMState
        if($cleanupOnError){
            Write-Output "Performing cleanup after error event..."
            $cleanup = CleanupTempResources -tempVirtualMachine $temporaryVm -tempNetworkInterface $temporaryNic -tempDisk $temporaryOSDisk -tempSnapshot $osDiskSnapshot
            Write-Output $cleanup
        }
        exit
    }
    elseif(!($tempVMState -like "*running*")){
        Write-Output "Attemping to start temp vm..."
        $startVM = StartVirtualMachine $temporaryVM.Name $temporaryVM.ResourceGroupName
        if($startVM -like "Error:*"){
            Write-Error $startVM
            if($cleanupOnError){
                Write-Output "Performing cleanup after error event..."
                $cleanup = CleanupTempResources -tempVirtualMachine $temporaryVm -tempNetworkInterface $temporaryNic -tempDisk $temporaryOSDisk -tempSnapshot $osDiskSnapshot
                Write-Output $cleanup
            }
            exit
        }
        else{
            Write-Output $startVM
        }
    }

    try{
        $vmExt = Get-AzVmCustomScriptExtension -ResourceGroupName $temporaryVM.ResourceGroupName -VMname $temporaryVM.Name -Name "ditwvdgeneralize" -ErrorAction SilentlyContinue
        if(!($vmExt)){
            # Get storage account key for auth to generalization script
            Write-Verbose "Getting script storage account key for: $scriptStorageAccountName"
            $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $scriptStorageAccountRG -AccountName $scriptStorageAccountName | Where-Object KeyName -eq "key1").value

            # Add the cusom script extension to the temp vm and run script
            Write-Output "Adding Custom Script Extension and executing generalization script. Script Name: $genScriptFileName, Script Container: $scriptContainerName"
            Set-AzVMCustomScriptExtension -ResourceGroupName $temporaryVM.ResourceGroupName -Location $temporaryVM.Location -VMName $temporaryVM.Name -Name "ditwvdgeneralize" -StorageAccountName $scriptStorageAccountName -StorageAccountKey $storageAccountKey -FileName $containerFiles -Run $genScriptFileName -ContainerName $scriptContainerName | Out-Null
            Write-Output "Custom Script Extension added sucessfully"
        }
        else{
            #throw "Custom script extension ditwvdgeneralize already exists and will not be re-added"
            Write-Output "Custom Script Extension already exists. Skipping..."
        }
    }
    catch{
        Write-Error $PSItem.Exception.Message
        if($cleanupOnError){
            Write-Output "Performing cleanup after error event..."
            $cleanup = CleanupTempResources -tempVirtualMachine $temporaryVm -tempNetworkInterface $temporaryNic -tempDisk $temporaryOSDisk -tempSnapshot $osDiskSnapshot
            Write-Output $cleanup
        }
        exit
    }

    # Wait for vm to stop. This means sysprep ran successfully via the custom script extension.
    $isStopped = $false
    $stopTryNum = 0
    While(!($isStopped) -and $stopTryNum -le 60){
        Write-Output "Waiting for temp vm to stop..."
        try{
            $tempVMState = GetAzureVMState $temporaryVM.Name $temporaryVM.ResourceGroupName
            if(($tempVMState -like "*stopped*")){
                $isStopped = $true
            }
            else{
                start-sleep -s 30
                $stopTryNum++
            }
        }
        catch{
            Write-Error $PSItem.Exception.Message
            break
        }
    }

    if($stopTryNum -ge 60 -and !($isStopped)){
        Write-Error "Timeout reached waiting for temp vm to stop after generalization"
        if($cleanupOnError){
            Write-Output "Performing cleanup after error event..."
            $cleanup = CleanupTempResources -tempVirtualMachine $temporaryVm -tempNetworkInterface $temporaryNic -tempDisk $temporaryOSDisk -tempSnapshot $osDiskSnapshot
            Write-Output $cleanup
        }
        exit
    }
    elseif(!($isStopped)){
        Write-Error "Error waiting for temp vm to stop after generalization"
        if($cleanupOnError){
            Write-Output "Performing cleanup after error event..."
            $cleanup = CleanupTempResources -tempVirtualMachine $temporaryVm -tempNetworkInterface $temporaryNic -tempDisk $temporaryOSDisk -tempSnapshot $osDiskSnapshot
            Write-Output $cleanup
        }
        exit
    }
    else{
        Write-Output "Temp VM stopped"
    }
}

# Deallocate temporary vm
Write-Output "Deallocating vm..."
$tempVMState = GetAzureVMState $temporaryVM.Name $temporaryVM.ResourceGroupName
if(!($tempVMState -like "*deallocated*")){
    $stopTempVM = StopVirtualMachine $temporaryVm.Name $temporaryVM.ResourceGroupName
    If($stopTempVM -like "Error:*"){
        Write-Error $stopTempVM
        if($cleanupOnError){
            Write-Output "Performing cleanup after error event..."
            $cleanup = CleanupTempResources -tempVirtualMachine $temporaryVm -tempNetworkInterface $temporaryNic -tempDisk $temporaryOSDisk -tempSnapshot $osDiskSnapshot
            Write-Output $cleanup
        }
        exit
    }
    else{
        Write-Output "Temporary vm is deallocated"
    }

}

# Set VM status to generalized
try{
    if($isGeneralized){
        Write-Output "Temp vm has already been generalized. Skipping..."
    }
    else{
        Write-Verbose "Setting vm status to Generalized..."
        Set-AzVm -ResourceGroupName $temporaryVM.ResourceGroupName -Name $temporaryVm.Name -Generalized | Out-Null
    }      
}
catch{
    Write-Error $PSItem.Exception.Message
    if($cleanupOnError){
        Write-Output "Performing cleanup after error event..."
        $cleanup = CleanupTempResources -tempVirtualMachine $temporaryVm -tempNetworkInterface $temporaryNic -tempDisk $temporaryOSDisk -tempSnapshot $osDiskSnapshot
        Write-Output $cleanup
    }
    exit
}

# Capture the managed image
Write-Output "Capturing managed image from temporary vm..."
$manImage = CaptureVirtualMachineImage $temporaryVM $imageName $imageResourceGroupName $getTimeStamp
if($manImage -like "Error:*"){
    Write-Error $manImage
    if($cleanupOnError){
        Write-Output "Performing cleanup after error event..."
        $cleanup = CleanupTempResources -tempVirtualMachine $temporaryVm -tempNetworkInterface $temporaryNic -tempDisk $temporaryOSDisk -tempSnapshot $osDiskSnapshot
        Write-Output $cleanup
    }
    exit
}
else{
    Write-Output "Managed image created successfully: $($manImage.Name) in $($manImage.ResourceGroupName)"
}

# Cleanup temporary resources
if($runCleanup){
    Write-Output "Performing cleanup..."
    $cleanup = CleanupTempResources -tempVirtualMachine $temporaryVm -tempNetworkInterface $temporaryNic -tempDisk $temporaryOSDisk -tempSnapshot $osDiskSnapshot
    Write-Output $cleanup
}