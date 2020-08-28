<#
.SYNOPSIS
    Restart session hosts exceeding a specified uptime on a recurring schedule
.DESCRIPTION
    This script is intended to be used via Azure Automation Account and executed on a recurring schedule to analyze session host uptime and initiate restarts as appropriate.
    Restarts will not be attempted within the configured peak hours or if the session host has active user sessions.
    If the session host vm does not return to a running state within 15 minutes, an alert email is generated and triggered by Microsoft Power Automate.
.NOTES
    Script is offered as-is with no warranty, expressed or implied.
    Author: Richard McIver
    Last Modified: 8/28/2020

    Required Automation Account Variables:

    RebootThreshold - The maximum up-time (in days) per session host before a restart is triggered
    StartPeakTime - Start of peak time (24-hour format). During peak times no restarts will be attempted.
    EndPeakTime	- End of peak time (24-hour format). During peak times no restarts will be attempted.
    HostPoolName - Name of the WVD host pool to manage
    HostPoolRg - Name of the Resource Group containing the host pool
    SessionHostVmRg	- Name of the Resource Group containing the session host virtual machines. May be the same Resource Group as the host pool.
    MSFlowURL - URL to the Power Automate Flow used to send the alert email
    EmailAddress - Email address to receive the alert email
    EmailSubject - Subject of the alert email
#>

Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
# Setting ErrorActionPreference to stop script execution when error occurs
$ErrorActionPreference = "Stop"

Function SendEmail($failedHosts){
    $emailBody = ""
    $emailBody += "<h4>Host Pool: $hostPoolName </h4>"
    ($failedHosts.Name).Split('/')[1] | %{ $emailBody += "$_<br/>"}
    $emailBody += "<br/><br/>"

    $emailBody = "<h1>Urgent: The WVD (ARM) session hosts listed below did not restart successfully and may be inaccessible.</h1> <br/>This message is the result of automation to periodically reboot session host virtual machines in Windows Virtual Desktop (ARM) production host pools. This is performed to maintain the health of the session host and operating system.</a><br/>" + `
        "<br/><br/><h2>Number of session hosts that failed to restart: $($failedHosts.Count)</h2> <br/><br/> <h3>Session Host List</h3>" + $emailBody + "<br/><br/><br/><br/><br/>"
       
     #Send Web Request to Flow to trigger email
    
        $JobUriParameters = New-Object PSObject -Property @{
        'emailAddress' = Get-AutomationVariable -Name 'EmailAddress';
        'emailSubject' = Get-AutomationVariable -Name 'EmailSubject';
        'emailBody' = $emailBody
    }

    $MSFlowParam = ConvertTo-Json -InputObject $JobUriParameters
    Invoke-WebRequest -Uri (Get-AutomationVariable -Name 'MSFlowURL') -ContentType "application/json" -Method POST -Body $MSFlowParam -UseBasicParsing
}

Function GetUptime($sHost)
{
    $funcOutput = ""
    $rebootNeeded = $false
    $vmName = (($sHost.Name) -split { $_ -eq '.' -or $_ -eq '/' })[1]
    Try{
        $vmStatus = (Get-AZVM -ResourceGroupName $sessionHostVmRg -Name $vmName -Status).Statuses
        $vmStartTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($vmStatus[0].Time, $tz)  
        $rebootDeadline = $date.AddDays(-$rebootThreshold)
        $upTime = $date - $vmStartTime
        If($rebootDeadline -ge $vmstartTime){
            $rebootNeeded = $true
        }
        Else{
            # Do nothing
        }
        
        $funcOutput = "HostPool: $($hostPool.Name); SessionHost: $vmName; StartTime: $vmStartTime; CurentTime: $date; UpTime: $upTime; RebootThreshold (Days): $rebootThreshold; RebootNeeded:$rebootNeeded"
    }
    Catch{
        $funcOutput = "Error getting session host uptime information: $($_.Exception.Message)"
    }

    Return $rebootNeeded, $funcOutput
}

Function RebootSessionHost($hostToReboot){
    $funcOutput = ""
    $statusTimeout = 60
    $hostRebooted = $false
    $newSessionsDisabled = $false
    $sHostName = $($hostToReboot.Name).Split('/')[1]
    $vmName = (($hostToReboot.Name) -split { $_ -eq '.' -or $_ -eq '/' })[1]
    Try{
        $getHost = Get-AzWvdSessionHost -ResourceGroupName $hostPoolRg -HostPoolName $hostPoolName -Name $sHostName
        If($getHost.Status -eq "Available" -and $getHost.session -eq 0){
            If($getHost.AllowNewSession -eq $true){
                Update-AzWvdSessionHost -ResourceGroupName $hostPoolRg -HostPoolName $HostPoolName -Name $sHostName -AllowNewSession:$false | Out-Null
                $newSessionsDisabled = $true
            }
            Restart-AzVM -ResourceGroupName $sessionHostVmRg -Name $vmName <#-NoWait#> | Out-Null
            $vmStatus = (Get-AZVM -ResourceGroupName $sessionHostVmRg -Name $vmName -Status).Statuses
            $vmState = ($vmStatus)[1].DisplayStatus
            $checkCount = 0
            While(!($vmState -like "*running*") -and $checkCount -lt $statusTimeout){
                Start-Sleep 15
                $checkCount++
                $vmStatus = (Get-AZVM -ResourceGroupName $sessionHostVmRg -Name $vmName -Status).Statuses
                $vmState = ($vmStatus)[1].DisplayStatus
            }

            If($checkCount -ge $statusTimeout)
            {
                $hostRebooted = "Timeout Reached"
            }
            
            If($newSessionsDisabled -and !($hostRebooted -eq "Timeout Reached")){
                Update-AzWvdSessionHost -ResourceGroupName $hostPoolRg -HostPoolName $HostPoolName -Name $sHostName -AllowNewSession:$true
                $hostRebooted = $true
            } 
        }
        
        $funcOutput = "HostPool: $($hostPool.Name); SessionHost: $vmName; HostRebooted: $hostRebooted"
    }
    Catch{
        $funcOutput = "HostPool: $($hostPool.Name); SessionHost: $vmName; Error rebooting session host: $($_.Exception.Message)"
    }

    return $hostRebooted, $funcOutput
}

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

$AzureContext = Get-AzSubscription -SubscriptionId $connection.SubscriptionID | Select-AzSubscription

#$setAzContext = Select-AzSubscription $AzureContext

if(!($AzureContext)){
    Write-Output "Please provide a valid subscription"
    exit
} 
else{
    $AzSubObj = $AzureContext | Out-String
    Write-Output "Sets the Azure subscription. Result: `n$AzSubObj"
}

Write-Output "Getting variables from automation"
# Set the uptime threshold (in days) for when session hosts vms will be restarted
$rebootThreshold = (Get-AutomationVariable -Name 'RebootThreshold')
If($rebootThreshold -lt 1){
    $rebootThreshold = 1
}

# Set peak times for the host pool. Session hosts will not be restarted during peak hours.
$startPeakTime = (Get-AutomationVariable -Name 'StartPeakTime')
$endPeakTime = (Get-AutomationVariable -Name 'EndPeakTime')
$timeZone = "Eastern Standard Time"
$peakDay = 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'

# Set host pool name and resource groups for the host pool and session hosts vms
$hostPoolName = (Get-AutomationVariable -Name 'HostPoolName')
$hostPoolRg = (Get-AutomationVariable -Name 'HostPoolRg')
$sessionHostVmRg= (Get-AutomationVariable -Name 'SessionHostVmRg')


# Calculate if we are in peak hours
$isPeakHour = $false
try{
    Write-Output "Calculating peak hours"
    
    $tz = Get-TimeZone $timeZone
    $utcDate = ((get-date).ToUniversalTime())
    $date = [System.TimeZoneInfo]::ConvertTimeFromUtc($utcDate, $tZ)
    $dateDay = $date.dayofweek
}
catch{
    Write-Error "Error getting current date and time information: $($_.Exception.Message)"
}

Write-Output "Current datetime: $date"
Write-Output "Current day: $dateDay"
Write-Output "Peak Time Start: $startPeakTime"
Write-Output "Peak Time End: $endPeakTime"
Write-Output "Peak Days: $peakDay"

try{
    If($utcDate.Date -gt $date.Date){
    $startPeakTime = (get-date $startPeakTime).AddDays(-1)
    $endPeakTime = (get-date $endPeakTime).AddDays(-1)
    }
    ElseIf($utcDate.Date -lt $date.Date){
        $startPeakTime = (get-date $startPeakTime).AddDays(1)
        $endPeakTime = (get-date $endPeakTime).AddDays(1)
    }
    Else{
        $startPeakTime = get-date $startPeakTime
        $endPeakTime = get-date $endPeakTime
    }
        
    if (($endPeakTime -lt $startPeakTime) -and ($date -gt $startPeakTime -or $date -lt $endPeakTime) -and $dateDay -in $peakDay) {
        $isPeakHour = $true
    } 
    elseif($date -gt $startPeakTime -and $date -lt $endPeakTime -and $dateDay -in $peakDay){
        $isPeakHour = $true
    }
    else{
        # Not in peak time
    }
}
catch{
    Write-Error "Error calculating peak time: $($_.Exception.Message)"
}

Write-Output "Is peak hours: $isPeakHour"

# Write-Host "HostPool: $hostPoolName; CurrentDateandTime: $date; TodayIs: $dateDay; PeakTimeStart: $startPeakTime; PeakTimeEnd: $endPeakTime; PeakDays: $peakDay; IsPeakHours: $isPeakHour"

If(!($isPeakHour)){
    try {
        Write-Output "Getting WVD host pool information: $hostPoolName"
        $hostPool = Get-AzWvdHostPool -ResourceGroupName $hostPoolRg -HostPoolName $hostPoolName
    }
    catch {
        Write-Error "Error getting host pool details: $($_.Exception.Message)"
    }

    try {
        Write-Output "Getting session host information"
        $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $hostPoolRg -HostPoolName $hostPoolName | Where-Object { $_.Status -eq "Available" }
        $runningSessionHostsCount = $sessionHosts.Count
        Write-Output "Running session hosts in pool: $runningSessionHostsCount"
        Write-Output "Running session hoss: $($sessionHosts.Name)"
    }
    catch {
        Write-Output "HostPool: $($hostPool.Name); Error getting session host details: $($_.Exception.Message)"
        break
    }

    # For each session host in the hsost pool, get its uptime and initiate a restart if needed
    $failedRestarts = @()
    foreach ($sessionHost in $sessionHosts) {
        If($sessionHost.session -gt 0){
            # Do nothing
            Write-Output "$($sessionHost.Name) has active user sessions. No action will be taken."
        }
        Else{
            $getUpTime = GetUptime $sessionHost
            $getUpTime[1]
            If($getUpTime[0]){
                $restartVM = RebootSessionHost $sessionHost
                $restartVM[1]
                If($restartVM[0]){
                    Write-Output "Session host was successfully restarted"
                }
                Else{
                    Write-Output "WARNING: Session host was not restarted"
                    $failedRestarts += $sessionHost.Name
                }
            }
            Else{
                # Do nothing
                Write-Output "$($sessionHost.Name): restart not required"
            }
        }
    }

    If($failedRestarts.Count -gt 0){
        SendEmail $failedRestarts
    }
}
Else{
    # Do nothing
    Write-Output "We are within peak hours for this host pool. No action will be taken at this time."
}