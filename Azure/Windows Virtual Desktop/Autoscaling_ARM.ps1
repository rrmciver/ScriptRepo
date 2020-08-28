# Input bindings are passed in via param block.
param($Timer)

<#
.SYNOPSIS
    Automated process of starting and stopping WVD session hosts based on user sessions.
.DESCRIPTION
    This script is intended to automatically start and stop session hosts in a Windows Virtual Desktop
    host pool based on the number of users.  
    The script determines the number of Session Hosts that should be running by adding the number of sessions 
    in the pool to a threshold. The threshold is the number of sessions available between each script run
    to accommodate new connections.  Those two numbers are added and divided by the maximum sessions per host.  
    The maximum session is set in the depth-first load balancing settings.  
    Session hosts are stopped or started based on the number of session hosts
    that should be available compared to the number of hosts that are running.

    Requirements:
    WVD Host Pool must be set to Depth First
    An Azure Function App
        Use System Assigned Managed ID
        Give contributor rights for the Session Host VM Resource Group to the Managed ID
   The script requires the following PowerShell Modules and are included in PowerShell Functions by default
        az.compute 
        az.desktopvirtualization
    For best results set a GPO to log out disconnected and idle sessions
    Full details can be found at:
    https://www.ciraltos.com/auto-start-and-stop-session-hosts-in-windows-virtual-desktop-spring-update-arm-edition-with-an-azure-function/
.NOTES
    Script is offered as-is with no warranty, expressed or implied.
    Test it before you trust it
    Author      : Travis Roberts
    Contributor : Kandice Hendricks
    Website     : www.ciraltos.com & https://www.greenpages.com/
    Version     : 1.0.0.0 Initial Build for WVD ARM.  Adapted from previous start-stop script for WVD Fall 2019
                    Updated for new az.desktopvirtulization PowerShell module and to run as a Function App

    Script modified to support additional functionality.
    Modified by: Richard McIver
    Last Modified: 7/30/2020

    - Added support for peak times that extend beyond midnight (e.g. start at 9:00 AM and ends at 4:00 AM the following morning)
    - Modified logging to support ingestion into Log Analytics
    - Added logic such that downscaling will not be attempted during peak hours
    - Added functionality to set a minimum number of available session hosts
    - Added support for breadth-first load balancing on host pools by changing serverStartThreshold to be percentage-based
    - Added support for forced logoff of disconnected user sessions when downscaling during off-peak hours and if no empty session hosts are available.
    - Added -NoWait paramter to Start-AzVM and Stop-AzVM functions to prevent script timeout errors
    - Corrected datetime calculation for peak hours when Azure Function is using UTC
    - Added support for a 0 minimum number of hosts. When set to 0, all session hosts will be powered off outside of peak hours if not in use.
#>


######## Variables ##########

# View Verbose data
# Set to "Continue" to see Verbose data
# set to "SilentlyContinue" to hide Verbose data
$VerbosePreference = "Continue"

# Server start threshold
# Number of available sessions to trigger a server start or shutdown
#$serverStartThreshold = 1

# Percentage (decimal value) of used sessions vs max available sessions to trigger start or stop of additional hosts
# Usage = TotalUserSessions / (AvailableSessionHosts * MaxSessionLimit)
$serverStartThreshold = 0.75

# Minimum number of sessions hosts to keep running at all times
$minSessionHosts = 0

# Peak time and Threshold settings
# Set usePeak to "yes" to enable peak time
# Set the Peak Threshold, Start and Stop Peak Time,
# Set the time zone to use, use "Get-TimeZone -ListAvailable" to list ID's
$usePeak = "yes"
$peakServerStartThreshold = 0.625
$startPeakTime = '06:00:00'
$endPeakTime = '23:59:59'
$timeZone = "Eastern Standard Time"
$peakDay = 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'

# Set force logoff behavior. If outside of peak hours, disconnected user sessions will be forced to log off as needed to downscale
$forceLogoff = "yes"

# Host Pool Name
$hostPoolName = 'MyHostPoolName'

# Session Host Resource Group
# Session Hosts and Host Pools can exist in different Resource Groups, but are commonly the same
# Host Pool Resource Group and the resource group of the Session host VM's.
$hostPoolRg = 'MyHostPoolResourceGroup'
$sessionHostVmRg= 'MySessionHostVMResourceGroup'

############## Functions ####################

Function Start-SessionHost {
    param (
        $sessionHosts,
        $hostsToStart
    )

    # Number of off session hosts accepting connections
    $offSessionHosts = $sessionHosts | Where-Object { $_.Status -eq "Unavailable" }
    $offSessionHostsCount = $offSessionHosts.count
    # Write-Verbose "Off Session Hosts $offSessionHostsCount"
    # Write-Verbose ($offSessionHosts | Out-String)
    if ($offSessionHosts.Count -eq 0 ) {
        Write-Error "HostPool: $($hostPool.Name); Error: Start threshold met or exceeded, but there are no hosts available in the pool to start"
    }
    else {
        if ($hostsToStart -gt $offSessionHostsCount) {
            $hostsToStart = $offSessionHosts
        }
        Write-Host "HostPool: $($hostPool.Name); SessionHoststoStartCount: $hostsToStart; StoppedSessionHostsCount: $offSessionHostsCount; StoppedSessionHosts:" ($offSessionHosts.name -join "," | Out-String)
        # Write-Verbose "Conditions met to start a host"
        $hostStarted = @()
        $counter = 0
        while ($counter -lt $hostsToStart) {
            $startServerName = ($offSessionHosts | Select-Object -Index $counter).name
            # Write-Verbose "Server to start $startServerName"
            try {
                # Start the VM
                $vmName = ($startServerName -split { $_ -eq '.' -or $_ -eq '/' })[1]
                Start-AzVM -ErrorAction Stop -ResourceGroupName $sessionHostVmRg -Name $vmName -NoWait
                $hostStarted += $startServerName
            }
            catch {
                $ErrorMessage = $_.Exception.message
                Write-Error ("HostPool: $($hostPool.Name); Error starting the vm: " + $ErrorMessage)
                Break
            }
            $counter++
        }
        Write-Host "HostPool: $($hostPool.Name); StartedSessionHostsCount: $counter; SessionHostsStarted:" ($hostStarted -join "," | Out-String)
    }
}

function Stop-SessionHost {
    param (
        $SessionHosts,
        $hostsToStop
    )
    # Get computers running with no users
    $emptyHosts = $sessionHosts | Where-Object { $_.Session -eq 0 -and $_.Status -eq 'Available' } | Sort-Object Name -Descending
    $emptyHostsCount = $emptyHosts.count
    $nonEmptyHosts = $sessionHosts | Where-Object { $_.Session -gt 0 -and $_.Status -eq 'Available' } | Select-Object -Property * | Sort-Object Session
    $nonEmptyHostsCount = $nonEmptyHosts.Count

    $hostsStopped = @()
    $usersLoggedOff = @()

    # Write-Verbose "Evaluating servers to shut down"

    if ($emptyHostsCount -eq 0 -and $forceLogoff -eq "no") {
        #Write-error "HostPool: $($hostPool.Name); Error: No hosts available to shut down"
        Write-Host "HostPool: $($hostPool.Name); No hosts available to stop at this time"
    }
    elseif($emptyHostsCount -eq 0 -and $forceLogoff -eq "yes"){
        $counter = 0
        while ($counter -lt $hostsToStop){
            $shutServerName = ($nonEmptyHosts | Select-Object -Index $counter).Name
            $vmName = ($shutServerName -split { $_ -eq '.' -or $_ -eq '/' })[1]
            $sHostName = $shutServerName.Split("/")[1]
            # Check to see if there are any active sessions
            Try{
                $sessions = Get-AzWvdUserSession -ResourceGroupName $hostPoolRg -HostPoolName $hostPoolName -SessionHostName $sHostName -ErrorAction Stop
            }
            Catch{
                Write-Error ("HostPool: $($hostPool.Name); Error getting session info from the vm: " + $ErrorMessage)
                break
            }

            If(($sessions | Where-Object SessionState -eq "Active").Count -gt 0){
                # There are actve users sessions on this host so do nothing
            }
            else {
                # There are no active users sessions, log off inactive sessions and stop vm
                try{
                    ForEach($session in $sessions){
                        $sessionID = ($session.Id).Split("/")[-1]
                        Remove-AzWvdUserSession -ResourceGroupName $hostPoolRg -HostPoolName $hostPoolName -SessionHostName $sHostName -Id $sessionID -Force
                        $usersLoggedOff += $session.UserPrincipalName
                    }
                    Stop-AzVM -ErrorAction Stop -ResourceGroupName $sessionHostVmRg -Name $vmName -Force -NoWait
                    $hostsStopped += $vmName
                }
                catch {
                    $ErrorMessage = $_.Exception.message
                    Write-Error ("HostPool: $($hostPool.Name); Error stopping the vm: " + $ErrorMessage)
                    Break
                }
            }
            $counter++
        }
    }
    else { 
        if ($hostsToStop -ge $emptyHostsCount) {
            $hostsToStop = $emptyHostsCount
        }
        # Write-Verbose "Conditions met to stop a host"
        Write-Host "HostPool: $($hostPool.Name); SessionHoststoStopCount: $hostsToStop; EmptySessionHostsCount: $emptyHostsCount; EmptySessionHosts:" ($emptyHosts.name -join "," | Out-String)
        $counter = 0
        while ($counter -lt $hostsToStop) {
            $shutServerName = ($emptyHosts | Select-Object -Index $counter).Name 
            #Write-Verbose "Shutting down server $shutServerName"
            try {
                # Stop the VM
                $vmName = ($shutServerName -split { $_ -eq '.' -or $_ -eq '/' })[1]
                Stop-AzVM -ErrorAction Stop -ResourceGroupName $sessionHostVmRg -Name $vmName -Force -NoWait
                $hostsStopped += $vmName
            }
            catch {
                $ErrorMessage = $_.Exception.message
                Write-Error ("HostPool: $($hostPool.Name); Error stopping the vm: " + $ErrorMessage)
                Break
            }
            $counter++
        }
    }

    If($hostsStopped.Count -gt 0){
        Write-Host "HostPool: $($hostPool.Name); StoppedSessionHostsCount: $counter; UsersLoggedOff:" ($usersLoggedOff -join "," | Out-String) "StoppedSessionHosts:" ($hostsStopped -join "," | Out-String)
    }
    else {
        Write-Host "HostPool: $($hostPool.Name); No hosts available to stop at this time"
    }

}   

########## Script Execution ##########

# Get Host Pool 
try {
    $hostPool = Get-AzWvdHostPool -ResourceGroupName $hostPoolRg -HostPoolName $hostPoolName -ErrorAction Stop
    # Write-Host "HostPool: $($hostPool.Name)"
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ("Error getting host pool details: " + $ErrorMessage)
    exit
}

# Verify load balancing is set to Depth-first
<#if ($hostPool.LoadBalancerType -ne "DepthFirst") {
    Write-Error "HostPool: $($hostPool.Name); Error: Host pool not set to Depth-First load balancing.  This script requires Depth-First load balancing to execute"
    exit
}#>

# Check if peak time and adjust threshold
# Warning! will not adjust for DST
if ($usePeak -eq "yes") {
    $isPeakHour = $false
    $utcDate = ((get-date).ToUniversalTime())
    $tZ = Get-TimeZone $timeZone
    $date = [System.TimeZoneInfo]::ConvertTimeFromUtc($utcDate, $tZ)
    # write-host "Current Date and Time: $date"
    # $dateDay = (((get-date).ToUniversalTime()).AddHours($utcOffset)).dayofweek
    $dateDay = $date.dayofweek
    # write-host "Today is: $dateDay"
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
        # Write-Verbose "Adjusting threshold for peak hours"
        $isPeakHour = $true
    } 
    elseif($date -gt $startPeakTime -and $date -lt $endPeakTime){
        $isPeakHour = $true
    }
    else{
        # Not in peak time
    }

    if($isPeakHour){
        $serverStartThreshold = $peakServerStartThreshold
    } 
    
    Write-Host "HostPool: $($hostPool.Name); CurrentDateandTime: $date; TodayIs: $dateDay; PeakTimeStart: $startPeakTime; PeakTimeEnd: $endPeakTime; PeakDays: $peakDay; IsPeakHours: $isPeakHour; UseThreashold:$serverStartThreshold"
}

# Get the Max Session Limit on the host pool
# This is the total number of sessions per session host
$maxSession = $hostPool.MaxSessionLimit
# Write-Host "HostPool: $($hostPool.Name), MaxSessions: $maxSession"

# Find the total number of session hosts
# Exclude servers in drain mode and do not allow new connections
try {
    $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $hostPoolRg -HostPoolName $hostPoolName | Where-Object { $_.AllowNewSession -eq $true }
    # Get current active user sessions
    $currentSessions = 0
    foreach ($sessionHost in $sessionHosts) {
        $count = $sessionHost.session
        $currentSessions += $count
    }
    # Write-Host "HostPool: $($hostPool.Name), CurrentSessions: $currentSessions"
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ("HostPool: $($hostPool.Name); Error getting session host details: " + $ErrorMessage)
    Break
}

# Number of running and available session hosts
# Host shut down are excluded
$runningSessionHosts = $sessionHosts | Where-Object { $_.Status -eq "Available" }
$runningSessionHostsCount = $runningSessionHosts.count
# Write-Host ($runningSessionHosts | Out-string)

#Calculating current max total user sessions for the pool
$maxPoolSessions = 0
$maxPoolSessions = $maxSession * $runningSessionHostsCount
If($maxPoolSessions -lt 1){
    $maxPoolSessions = 1
}

# Calculating percentage of sessions in use vs max available sessions
If($currentSessions -lt 1)
{
    $actualUsage = 0
}
Else
{
    $actualUsage = $currentSessions / $maxPoolSessions
}

# Setting target value for the number of running session hosts
If($runningSessionHostsCount -lt $minSessionHosts)
{
    $sessionHostTarget = $minSessionHosts
}
Else
{
    $sessionHostTarget = $runningSessionHostsCount
}

# Calculating number of running session hosts needed based on configured threshold

# If actual usage exceeds the threshold of if the number of running hosts does not meet the min expected, calculate how many session hosts should be running
If($actualUsage -ge $serverStartThreshold -or ($isPeakHour -and $runningSessionHostsCount -lt 1))
{
    $sessionHostTarget = $runningSessionHostsCount + 1
}
ElseIf($actualUsage -lt $serverStartThreshold)
{
    # Actual usage is below threshold. Verify we meet min session hosts and calculate new actual usage if we downscale.
    If($runningSessionHostsCount -gt $minSessionHosts)
    {
        If($runningSessionHostsCount -eq 1){
            $downScaleResult = 0
        }
        elseif($runningSessionHostsCount -gt 1){
           $downScaleResult = $currentSessions / (($runningSessionHostsCount - 1) * $maxSession)
        }
        Else{
            Write-Error ("HostPool: $($hostPool.Name); Error calculating result of potential downscale operation")
        }

        If($downScaleResult -ge $serverStartThreshold)
        {
            # Do nothing as downscaling would result in actual usage exceeding the threshold
        }
        ElseIf($downScaleResult -lt $serverStartThreshold)
        {
            # Downscaling will resut in actual usage being below the threshold. Safe to continue.
            $sessionHostTarget = $runningSessionHostsCount - 1
        }
        Else
        {
            Write-Error ("HostPool: $($hostPool.Name); Error calculating result of potential downscale operation")
        }
    }
    Else
    {
        # Do nothing
    }
}
Else
{
    # No change to session host target
}

# Target number of servers required running based on active sessions, Threshold and maximum sessions per host
#$sessionHostTarget = [math]::Ceiling((($currentSessions + $serverStartThreshold) / $maxSession))

Write-Host "HostPool: $($hostPool.Name); RunningSessionHostsCount: $runningSessionHostsCount; MaxSessionsPerHost: $maxSession; AvailableSessons: $($maxSession * $runningSessionHostsCount); CurrentUserSessions: $currentSessions; RunningSessionHostsTarget: $sessionHostTarget; RunningSessionHosts:" ($runningSessionHosts.name -join "," | Out-String) 

if ($runningSessionHostsCount -lt $sessionHostTarget) {
    # Write-Verbose "Running session host count $runningSessionHosts is less than session host target count $sessionHostTarget, run start function"
    $hostsToStart = ($sessionHostTarget - $runningSessionHostsCount)
    Start-SessionHost -sessionHosts $sessionHosts -hostsToStart $hostsToStart
}
elseif ($runningSessionHostsCount -gt $sessionHostTarget) {
    # Write-Verbose "Running session hosts count $runningSessionHostsCount is greater than session host target count $sessionHostTarget, run stop function"
    If($usePeak -eq "yes" -and $isPeakHour){
        # Write-Verbose "Running session hosts count of $runningSessionHostsCount is greater than session host target count $sessionHostTarget, but we are inside peak hours. No session hosts will be stopped"
    }
    else{
        $hostsToStop = ($runningSessionHostsCount - $sessionHostTarget)
        Stop-SessionHost -SessionHosts $sessionHosts -hostsToStop $hostsToStop
    }
}
else {
    # Write-Verbose "Running session host count $runningSessionHostsCount matches session host target count $sessionHostTarget, doing nothing"
}