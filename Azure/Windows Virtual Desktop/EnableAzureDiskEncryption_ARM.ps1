<#
.SYNOPSIS
    Automate the process to enable Azure Disk Encrpytiong on WVD session hosts. Intended for the WVD Spring 2020 update (ARM).

.DESCRIPTION
    This script is inteded to be used to automate the process of enabling Azure Disk Encryption (ADE) on all unencrypted session hosts in a WVD host pool without impacting users. It is designed to be run as an Auotmation Account runbook.
    Permissions:  
    The RunAs account of your Azure Automation Account must have the Contributor role to either your WVD subscription or the Reosurce Groups containg the WVD host pool and session host virtual machines.
    It must also have at least Read permissions to the Resource Group contianing the desired KeyVault.
.NOTES
    Script is offered as-is with no warranty, expressed or implied.
    Author: Richard McIver
    Last Modified: 7/20/2020

    Required Variables:
    AADTenenatId - Azure TenantID
    AzureRunAsName - Run As account connection asset name
    KeyName - Name of the key within the KeyVault to use for disk encryption
    KeyVaultName - Name of the KeyVault containing the desired key
    KeyVaultResourceGroup - Name of the Resource Group containing the KeyVault and Key
    SubscriptionName - Name of the subscription containing the WVD resources

    Use: When executed, the RunBook will prompt for the following input:
    HOSTPOOLNAME - Name of the host pool containing the session hosts to be encrypted
    ALLOWSTARTVM (True/False) - If an unencrypted session host is stopped, allow the script to start it
    ALLOWNEWSESSIONS (True/False) - If set to True, once ADE has been enabled on the session host the script will re-enable the AllowNewSession flag. If set to False, AllowNewSession will remain disabled until manually re-enabled by an admin.
    OVERRIDEHOSTLIMIT (True/False) - If set to False, the script will ensure at least one session host in the pool remains available to accept user sessions during execution. If set to True, the script will disable AllowNowSession on all session hosts without regard for the number of available hosts in the pool.
#>

param(
    
    [Parameter(Mandatory=$true)]
    [string]$HostPoolName,
    
    [Parameter(Mandatory=$true)]
    [bool]$AllowStartVM,

    [Parameter(Mandatory=$true)]
    [bool]$AllowNewSessions,

    [Parameter(Mandatory=$true)]
    [bool]$overrideHostLimit
)

#Collect the credentials from Azure Automation Account Assets
$Connection = Get-AutomationConnection -Name (Get-AutomationVariable -Name 'AzureRunAsName')

#Authenticating to Azure
Clear-AzContext -Force
$AZAuthentication = Connect-AzAccount -ApplicationId $Connection.ApplicationId -TenantId (Get-AutomationVariable -Name 'AADTenantId') -CertificateThumbprint $Connection.CertificateThumbprint -ServicePrincipal
if ($AZAuthentication -eq $null) {
Write-Output "Failed to authenticate Azure: $($_.exception.message)"
exit
} else {
$AzObj = $AZAuthentication | Out-String
Write-Output "Authenticating as service principal for Azure. Result: `n$AzObj"
}
#Set the Azure context with Subscription
$AzContext = Set-AzContext -Subscription (Get-AutomationVariable -Name 'SubscriptionName')
if ($AzContext -eq $null) {
Write-Error "Please provide a valid subscription"
exit
} else {
$AzSubObj = $AzContext | Out-String
Write-Output "Sets the Azure subscription. Result: `n$AzSubObj"
}

function Get-WVDHosts{

    param(
		[string]$resourceGroup,
		[string]$hostPool
	)

    try{
        $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $resourceGroup -HostPoolName $hostPool -ErrorAction Stop
    }
	catch{
        $_
    }
	return $sessionHosts
}

function Get-WVDResourceGroupName($hostPool){
    # Extract the host pool's resource group from its resource id
    $resourceID = $hostPool.Id
    $rgName = $resourceID.split("/")[4]
    return $rgName
}

function Get-AzureVMPowerState($azvm){
    $isOn = $false
    if($azvm.PowerState -like "*running*"){
        $isOn = $true
    }
    else{
        # vm is not running
    }
    
    return $isOn
}

function Start-SessionHostVM($azvmName){
    $IsVMStarted = $false
    try{
        $azvmInfo = Get-AzVM -Name $azvmName -Status -ErrorAction Stop
        if($azvmInfo.PowerState -notlike "*running*"){
            $azvmInfo | Start-AzVM -AsJob | Out-Null
            while (!$IsVMStarted){
                $RoleInstance = get-azvm -Name $azvmName -Status
                if($RoleInstance.PowerState -like "*running*"){
                    $IsVMStarted = $true
                    Write-Output "$azvmName is now running"
                 }
                else{
                    Start-Sleep -Seconds 10
                }
            }
        }
    }
    catch{
        $_
    }
    
    return $IsVMStarted
}

$countofhosts = 0

$hostPool = Get-AzWvdHostPool | Where-Object Name -eq $HostPoolName

If(!$hostPool){
    Write-Output "Unable to get host pool: $HostPoolName"
    exit
}

$resourceGroupName = Get-WVDResourceGroupName $hostPool

#Get a list of hosts
$sessionHosts = Get-WVDHosts -resourceGroup $resourceGroupName -hostPool $hostPoolName
$countofhosts = $sessionHosts.count

#Check Encryption Status and generate list of vms to take action against
$listofnotencrypted = @()

foreach ($vm in $sessionHosts){
    #Get VM Information
    $vmName = (($vm.Name).Split("/")[1]).split(".")[0]
    $hostName = ($vm.Name).Split("/")[1]
    try{
        $vmInfo = Get-AzVM -Name $vmName -ErrorAction Stop
    }
    catch{
        $_
        continue
    }

    #Get Encryption Status
    $status = ""
    $status = (Get-AzDisk -ResourceGroupName $vminfo.ResourceGroupName -DiskName $vminfo.StorageProfile.OsDisk.Name).EncryptionSettingsCollection

    if(!$status)
    {
        $listofnotencrypted += $hostName
        Write-Output "$vmName is not encrypted. Will attempt to enable ADE"
    } 
    else {
        Write-Output "$vmName is already encrypted. No additional action will be taken"
    }
}

Write-Output "Found $($listofnotencrypted.count) of $countofhosts unencrypted hosts in the host pool"

# Attempt to enable Encryption
$keyVaultName = Get-AutomationVariable -Name 'KeyVaultName'
$keyRG = Get-AutomationVariable -Name 'KeyVaultResourceGroup'
$keyName = Get-AutomationVariable -Name 'KeyName'

try{
    $KeyVault = Get-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $keyRG -ErrorAction Stop
    $keyVaultKey = Get-AzKeyVaultKey -VaultName $keyVaultName -Name $keyName -ErrorAction Stop
}catch{
    write-output "Error getting Key Vault information: $($_.exception.message)"
    exit
}

# Check session host power states and generate list of vms to encrypt
$hostsToEncrypt = @()
foreach ($azureVM in $listofnotencrypted){
    $vmName = $azureVM.Split(".")[0]
    try{
        $vmStatus = Get-AzVM -NAme $vmName -Status -ErrorAction Stop
    }
    catch{
        $_
        continue
    }
    
    $pwState = Get-AzureVMPowerState $vmStatus

    If(!($pwState) -and ($AllowStartVM)){
        write-output "$vmName is not running. Attempting to start..."
        If(!(Start-SessionHostVM $vmName)){
            write-output "$vmName is not in a running state and could not be started. Investigate the state of the virtual machine and manualy enabe ADE if needed."
            continue
        }
        
        $hostsToEncrypt += $azureVM
    }
    elseif(!($pwState)){
        write-output "$vmName is not in a running state and cannot be encrypted. Set the AllowStartVM parameter to TRUE to allow the script to start vms as needed."
        continue
    }
    else{
        $hostsToEncrypt += $azureVM
    }    
}

If($hostsToEncrypt.count -gt 0){
    ForEach($vm in $hostsToEncrypt){
        $vmName = $vm.Split(".")[0]
        # Check if VM has active sessions
        $sessionHostInfo = Get-AzWvdSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $HostPoolName -Name $vm
        if($sessionhostinfo.Session -gt 0){
            write-output "$vmName has $($sessionhostinfo.Session) active user sessions. No action will be taken at ths time."
            continue
        }

        # Disable allow new user sessions
        if($sessionhostinfo.AllowNewSession)
        {
            $hostsAllowingNewSessions = 0
            If(!($overrideHostLimit))
            {
                $avHosts = Get-WVDHosts -resourceGroup $resourceGroupName -hostPool $hostPoolName
                ForEach($avHost in $avHosts)
                {
                    If($avHost.AllowNewSession)
                    {
                        $hostsAllowingNewSessions++
                    }
                }
            }
            
            If($hostsAllowingNewSessions -gt 1 -or ($overrideHostLimit)){
                write-output "Disabling AllowNewSesion flag on $vmName to prevent new user sessions while ADE is enabled"
                try{
                    Update-AzWvdSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $HostPoolName -Name $vm -AllowNewSession:$false
                }
                catch{
                    Write-Host "Unable to disable AllowNewSession for $($vmName): $_"
                    continue
                }
            }
            Else{
                Write-Output "Unable to disable AllowNewSession for $($vmName) due to session host availability threashhold."
                continue
            }
            
        }

        # Attempt to enable ADE on the host
        try{
            write-output "Enabling Azure drive encryption on $vmName. The VM will be restarted..."
            Set-AzVMDiskEncryptionExtension -ResourceGroupName $resourceGroupName -VMName $vmName -DiskEncryptionKeyVaultUrl $KeyVault.VaultUri -DiskEncryptionKeyVaultId $KeyVault.ResourceId -KeyEncryptionKeyUrl $keyVaultKey.Key.Kid -KeyEncryptionKeyVaultId $KeyVault.ResourceId -VolumeType All -Force -ErrorAction Stop
            write-output "ADE has been successfully enabled on $vmName. Data encryption is still in progress. Current encryption status can be checked via the Azure Portal or on the VM itself"

        }catch{
            write-output "Error when trying to enable encryption on Azure VM $vmName. Error: $($_.exception.message)"
        }

        If($AllowNewSessions){
            write-output "Re-enabling AllowNewSesion to allow any users to connect to the session host."
            write-output  "Note that performance may be degraded while encryption is in progress"
            Update-AzWvdSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $HostPoolName -Name $vm -AllowNewSession:$true
        }
    }
}
Else{
    write-output "No session hosts are available at this time for ADE enforcement"
}

Write-output "Runbook Finished."
