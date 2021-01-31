<# 
 Description: This script is used to generalize the operating system and prepare it for capture as a deployable image for Windows Virtual Desktop
 
 Recommended Use: This script can be executed manually on the target os, but it is intended to be used in congunction with Azure Automation for WVD image capture.
    WVD-Generalize-VM-aa.ps1 and supporting files should be located on an Azre Storage Account accessible from the target vm, and executed via the CustomScriptExtension for Azure VMs.

 Notes:
 Some portions of this script are redundant to support legacy image deployment via the WVDAdmin utility.
 Support for WVDAdmin requires the following files to be co-located with this script when exeucted:
    -ITPC-WVD-Image-Processing.ps1
    -Microsoft.RDInfra.RDAgent.msi
    -Microsoft.RDInfra.RDAgentBootLoader.msi

 See the WVDAdmin website for more information: https://blog.itprocloud.de/Windows-Virtual-Desktop-Admin/

 IMPORTANT: When complete, sysprep will be executed and the system will be shut down. At this point the Azure VM will no longer be usable.
#>

function StopScript(){
    Stop-Transcript
    exit
}

# Define logfile
$LogDir="$env:windir\system32\logfiles"
$LogFile=$LogDir+"\WVD.Generalizing.log"
$osConfigPath = "C:\osconfig"
$wvdAdminPath = "C:\ITPC-WVD-PostCustomizing"
$wvdAdminScript = "ITPC-WVD-Image-Processing.ps1"

Start-Transcript $LogFile -Force

# Check to see if OS is Windows 7
If([System.Environment]::OSVersion.Version.Major -gt 6)
{
    $isWin10 = $true
    Write-Host "OS version is Windows NT 10 or later"
}
else{
    $isWin10 = $false
    Write-Host "OS is Windows NT 6 or older"
}

# Verify WVD agents are available locally and download them if needed (msis are renamed to make the reference version agnostic)
Write-Host "Verfy WVD agent installation files are available on the local session host for WVDAdmin"

If(!(Test-Path $osConfigPath)){
    New-Item -ItemType "directory" -Path $osConfigPath -ErrorAction Ignore
    (Get-Item $osConfigPath).attributes="Hidden"
}

If(!(Test-Path $wvdAdminPath)){
    New-Item -ItemType "directory" -Path $wvdAdminPath -ErrorAction Ignore
    (Get-Item $wvdAdminPath).attributes="Hidden"
}

# Copy msis for legacy support for WVDAdmin
Copy-Item "$PSScriptRoot\$wvdAdminScript" -Destination ($wvdAdminPath+"\")
Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgent.msi" -Destination ($wvdAdminPath+"\")
Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgentBootLoader.msi" -Destination ($wvdAdminPath+"\")

# Copy msis to osconfig folder
Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgent.msi" -Destination ($osConfigPath+"\")
Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgentBootLoader.msi" -Destination ($osConfigPath+"\")

Write-Host "Removing existing Remote Desktop Agent Boot Loader"
$app=Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -match "Remote Desktop Agent Boot Loader"}
if($app -ne $null){
    $app.uninstall()
}

Write-Host "Removing existing Remote Desktop Services Infrastructure Agent"
$app=Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -match "Remote Desktop Services Infrastructure Agent"}
if($app -ne $null){
    $app.uninstall()
}
Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\RDMonitoringAgent" -Force -ErrorAction Ignore

Write-Host "Disabling ITPC-LogAnalyticAgent and MySmartScale if exist"
Disable-ScheduledTask  -TaskName "ITPC-LogAnalyticAgent for RDS and Citrix" -ErrorAction Ignore
Disable-ScheduledTask  -TaskName "ITPC-MySmartScaleAgent" -ErrorAction Ignore

Write-Host "Cleaning up reliability messages"
$key="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Reliability"
Remove-ItemProperty -Path $key -Name "DirtyShutdown" -ErrorAction Ignore
Remove-ItemProperty -Path $key -Name "DirtyShutdownTime" -ErrorAction Ignore
Remove-ItemProperty -Path $key -Name "LastAliveStamp" -ErrorAction Ignore
Remove-ItemProperty -Path $key -Name "TimeStampInterval" -ErrorAction Ignore

Write-Host "Modifying sysprep to avoid issues with AppXPackages"
$sysPrepActionPath="$env:windir\System32\Sysprep\ActionFiles"
$sysPrepActionFile="Generalize.xml"
$sysPrepActionPathItem = Get-Item $sysPrepActionPath.Replace("C:\","\\localhost\\c$\")
$acl = $sysPrepActionPathItem.GetAccessControl()
$acl.SetOwner((New-Object System.Security.Principal.NTAccount("SYSTEM")))
$sysPrepActionPathItem.SetAccessControl($acl)
$aclSystemFull = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM","FullControl","Allow")
$acl.AddAccessRule($aclSystemFull)
$sysPrepActionPathItem.SetAccessControl($acl)
[xml]$xml = Get-Content -Path "$sysPrepActionPath\$sysPrepActionFile"
$xmlNode=$xml.sysprepInformation.imaging | where {$_.sysprepModule.moduleName -match "AppxSysprep.dll"}
if ($xmlNode -ne $null) {
    $xmlNode.ParentNode.RemoveChild($xmlNode)
    $xml.sysprepInformation.imaging.Count
    $xml.Save("$sysPrepActionPath\$sysPrepActionFile.new")
    Remove-Item "$sysPrepActionPath\$sysPrepActionFile.old" -Force -ErrorAction Ignore
    Move-Item "$sysPrepActionPath\$sysPrepActionFile" "$sysPrepActionPath\$sysPrepActionFile.old"
    Move-Item "$sysPrepActionPath\$sysPrepActionFile.new" "$sysPrepActionPath\$sysPrepActionFile"
    Write-Host "Modifying sysprep to avoid issues with AppXPackages - Done"
}

Write-Host "Saving time zone info for re-deploy"
$timeZone=(Get-TimeZone).Id
Write-Host "Current time zone is: "+$timeZone
New-Item -Path "HKLM:\SOFTWARE" -Name "UMDWVD" -ErrorAction Ignore
New-Item -Path "HKLM:\SOFTWARE\UMDWVD" -Name "WVD.Runtime" -ErrorAction Ignore
New-ItemProperty -Path "HKLM:\SOFTWARE\UMDWVD\WVD.Runtime" -Name "TimeZone.Origin" -Value $timeZone -force

# Saving timezone for legacy WVDAdmin support
New-Item -Path "HKLM:\SOFTWARE" -Name "ITProCloud" -ErrorAction Ignore
New-Item -Path "HKLM:\SOFTWARE\ITProCloud" -Name "WVD.Runtime" -ErrorAction Ignore
New-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -Name "TimeZone.Origin" -Value $timeZone -force

Write-Host "Starting sysprep to generalize session host..."
if ($isWin10){
	Write-Host "Starting sysprep and shutting down vm. See sysprep log file for additional detail"
    Stop-Transcript
    Start-Process -FilePath "$env:windir\System32\Sysprep\sysprep" -ArgumentList "/generalize /oobe /shutdown /mode:vm"
} 
else {
    #Windows 7 / 8
    Write-Host "Enabling RDP8 on Windows 7"
    New-Item -Path "HKLM:\SOFTWARE" -Name "Policies" -ErrorAction Ignore
    New-Item -Path "HKLM:\SOFTWARE\Policies" -Name "Microsoft" -ErrorAction Ignore
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft" -Name "Windows NT" -ErrorAction Ignore
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT" -Name "Terminal Services" -ErrorAction Ignore
    New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fServerEnableRDP8" -Value 1 -force

    Write-Host "Starting sysprep and shutting down vm. See sysprep log file for additional detail"
    Stop-Transcript
    Start-Process -FilePath "$env:windir\System32\Sysprep\sysprep" -ArgumentList "/generalize /oobe /shutdown"
}