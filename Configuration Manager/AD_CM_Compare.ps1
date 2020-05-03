<#
AD_CM_Compare.ps1
Author: Richard McIver
Last Edit: 5/3/2020
Description: Compare active computer objects in Active Directory with clients in Configuration Manager to indentify potentiially unmanaged devices.
Use: PowerShell.exe -executionpolicy bypass -file "AD_CM_Compare.ps1"
Notes:
- This script leverages both the Active Directory and ConfigMgr PowerShell modules.
- Be sure to run this script on a system with the Configuration Manager administration console and Active Directory RSAT tools installed.
- A list of active domain joined clients that do not exist in the provided ConfigMgr collection will be written to the ADCMCompare.txt file in the user temp directory.
#>

# Import PS modules
Import-Module ActiveDirectory
Import-Module "$env:SMS_ADMIN_UI_PATH\..\configurationmanager.psd1"

# Establish output file
$outFile = "$env:TEMP\ADCMCompare_$(Get-Date -uformat '%m-%d-%y-%I-%M').csv"

# Set the Active Directory search base for finding active computers
$searchBase = "OU=Computers,DC=MyDomain,DC=com"

# Configuration Manager collection ID to get the list 
$smsCollection = "SMS00001"

# Find and set the CM site code
$siteCode = $(Get-WMIObject -ComputerName "$env:ComputerName" -Namespace "root\sms" -class "SMS_ProviderLocation" -ErrorAction SilentlyContinue).SiteCode 

If (!($siteCode))
{
   # $siteCode = $([WmiClass]"\\localhost\ROOT\ccm:SMS_Client").GetAssignedSite()
    $siteCode = (Get-ItemProperty -Path "HKLM:SOFTWARE\Microsoft\SMS\Mobile Client").AssignedSiteCode
}

# Change location to the CM site
Set-Location "$($siteCode):"

# Get all computer objects in the specified domain and OU, excluding Disabled objects
$adComputers = Get-ADComputer -Filter * -SearchBase $searchBase -properties OperatingSystem, Enabled, CanonicalName | Where-Object {$_.Enabled -eq 'TRUE'} | Select-Object Name, OperatingSystem, Enabled, CanonicalName

# Get all devices in the specified ConfigMgr collection
$cmDevices = Get-CMcollectionMember -CollectionID $smsCollection | Select-Object Name 

# Compare the two lists to find AD computers not in the ConfigMgr site
$compare = Compare-Object $cmDevices $adComputers -property Name | Where-Object SideIndicator -eq '=>' 

# Export the list of unmanaged devices to the output file
$adComputers | Where-Object {$_.Name -IN $compare.Name} | Export-CSV $outfile -NoTypeInformation -Encoding UTF8 -Force

