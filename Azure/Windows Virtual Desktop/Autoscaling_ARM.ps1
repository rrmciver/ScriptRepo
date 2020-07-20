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

    IMPORTANT: This script has been modified from it's origional source to support additional functionality. All previous comments and notes still apply.
    Additional Contributor(s): Richard McIver
    Changes:
    -Added support for peak times that span days. For example, start peak time of 09:00:00 and end peak time of 04:00:00. Peak time runs through midnight and into the next morning.
    -Added -NoWait paramter to Stop-AzVM in the Stop-SessionHost function to avoid timeout issues in some circumstances.
    -Added logic such that session hosts will no longer be scaled down (powered off) if within peak hours.
    -Added custom output to better support injestion into Log Analytics.
#>


######## Variables ##########

# View Verbose data
# Set to "Continue" to see Verbose data
# set to "SilentlyContinue" to hide Verbose data
$VerbosePreference = "Continue"

# Server start threshold
# Number of available sessions to trigger a server start or shutdown
$serverStartThreshold = 2

# Peak time and Threshold settings
# Set usePeak to "yes" to enable peak time
# Set the Peak Threshold, Start and Stop Peak Time,
# Set the time zone to use, use "Get-TimeZone -ListAvailable" to list ID's
$usePeak = "yes"
$peakServerStartThreshold = 3
$startPeakTime = '06:00:00'
$endPeakTime = '23:59:59'
$timeZone = "Eastern Standard Time"
$peakDay = 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'

# Host Pool Name
$hostPoolName = ''

# Session Host Resource Group
# Session Hosts and Host Pools can exist in different Resource Groups, but are commonly the same
# Host Pool Resource Group and the resource group of the Session host VM's.
$hostPoolRg = ''
$sessionHostVmRg= ''

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
        Write-Error "HostPool: $($hostPool.Name); Error: Start threshold met, but there are no hosts available to start"
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
                Start-AzVM -ErrorAction Stop -ResourceGroupName $sessionHostVmRg -Name $vmName
                $hostsStarted += $startServerName
            }
            catch {
                $ErrorMessage = $_.Exception.message
                Write-Error ("HostPool: $($hostPool.Name); Error starting the vm: " + $ErrorMessage)
                Break
            }
            $counter++
        }
        Write-Host "HostPool: $($hostPool.Name); StartedSessionHostsCount: $counter; SessionHostsStarted:" ($hostsStarted -join "," | Out-String)
    }
}

function Stop-SessionHost {
    param (
        $SessionHosts,
        $hostsToStop
    )
    # Get computers running with no users
    $emptyHosts = $sessionHosts | Where-Object { $_.Session -eq 0 -and $_.Status -eq 'Available' }
    $emptyHostsCount = $emptyHosts.count
    # Write-Verbose "Evaluating servers to shut down"

    if ($emptyHostsCount -eq 0) {
        Write-error "HostPool: $($hostPool.Name); Error: No hosts available to shut down"
    }
    else { 
        if ($hostsToStop -ge $emptyHostsCount) {
            $hostsToStop = $emptyHostsCount
        }
        # Write-Verbose "Conditions met to stop a host"
        Write-Host "HostPool: $($hostPool.Name); SessionHoststoStopCount: $hostsToStop; EmptySessionHostsCount: $emptyHostsCount; EmptySessionHosts:" ($emptyHosts.name -join "," | Out-String)
        $hostsStopped = @()
        $counter = 0
        while ($counter -lt $hostsToStop) {
            $shutServerName = ($emptyHosts | Select-Object -Index $counter).Name 
            #Write-Verbose "Shutting down server $shutServerName"
            try {
                # Stop the VM
                $vmName = ($shutServerName -split { $_ -eq '.' -or $_ -eq '/' })[1]
                Stop-AzVM -ErrorAction Stop -ResourceGroupName $sessionHostVmRg -Name $vmName -Force -NoWait
                $hostsStopped += $shutServerName
            }
            catch {
                $ErrorMessage = $_.Exception.message
                Write-Error ("HostPool: $($hostPool.Name); Error stopping the vm: " + $ErrorMessage)
                Break
            }
            $counter++
        }
        Write-Host "HostPool: $($hostPool.Name); StoppedSessionHostsCount: $counter; StoppedSessionHosts:" ($hostsStopped -join "," | Out-String)
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
if ($hostPool.LoadBalancerType -ne "DepthFirst") {
    Write-Error "HostPool: $($hostPool.Name); Error: Host pool not set to Depth-First load balancing.  This script requires Depth-First load balancing to execute"
    exit
}

# Check if peak time and adjust threshold
# Warning! will not adjust for DST
if ($usePeak -eq "yes") {
    $isPeakHour = $false
    $utcDate = ((get-date).ToUniversalTime())
    $tZ = Get-TimeZone $timeZone
    $date = [System.TimeZoneInfo]::ConvertTimeFromUtc($utcDate, $tZ)
    # write-host "Current Date and Time: $date"
    $dateDay = (((get-date).ToUniversalTime()).AddHours($utcOffset)).dayofweek
    # write-host "Today is: $dateDay"
    $startPeakTime = get-date $startPeakTime
    $endPeakTime = get-date $endPeakTime
    If($endPeakTime -lt $startPeakTime)
    {
        $endPeakTime = $endPeakTime.AddDays(1)
    }
    if ($date -gt $startPeakTime -and $date -lt $endPeakTime -and $dateDay -in $peakDay) {
        # Write-Verbose "Adjusting threshold for peak hours"
        $isPeakHour = $true
        Write-Host "HostPool: $($hostPool.Name); CurrentDateandTime: $date; TodayIs: $dateDay; PeakTimeStart: $startPeakTime; PeakTimeEnd: $endPeakTime; PeakDays: $peakDay; IsPeakHours: $isPeakHour"
        $serverStartThreshold = $peakServerStartThreshold
    } 
    else{
        Write-Host "HostPool: $($hostPool.Name); CurrentDateandTime: $date; TodayIs: $dateDay; PeakTimeStart: $startPeakTime; PeakTimeEnd: $endPeakTime; PeakDays: $peakDay; IsPeakHours: $isPeakHour"
    }
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

# Target number of servers required running based on active sessions, Threshold and maximum sessions per host
$sessionHostTarget = [math]::Ceiling((($currentSessions + $serverStartThreshold) / $maxSession))

Write-Host "HostPool: $($hostPool.Name); RunningSessionHostsCount: $runningSessionHostsCount; MaxSessionsPerHost: $maxSession; AvailableSessons: $($maxSession*$runningSessionHostsCount); CurrentUserSessions: $currentSessions; RunningSessionHostsTarget: $sessionHostTarget; RunningSessionHosts:" ($runningSessionHosts.name -join "," | Out-String) 

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