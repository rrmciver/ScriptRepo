Function TestSiteConnection
{
    Write-Host "Testing connection to SCCM site server..."
    If (Test-Connection $siteServerName)
    {
        Write-Host "Success"
        Write-Host "Testing VPN connection..."
        $testVPN = Get-WMIObject -Query $vpnQuery
        If ($testVPN)
        {
            Write-Host "WARNING: VPN connection detected"
            Return $false
        }
        Else
        {
            Write-Host "VPN not detected"
            Return $true
        }
    }
    ELSE
    {
        Write-Host "Failed to connect. Possible external network connection"
        Return $false
    }
}

Function OnError ($msg)
{
    Write-Host $msg
    Stop-Transcript
    EXIT
}

Start-Transcript "C:\Windows\Temp\ExecuteTaskSequence.log" -Append -Force
$siteServerName = "CM1"
$programID = "*"
$schTaskName = "Run Task Sequence On Logon"
$vpnQuery = "Select * from Win32_NetworkAdapterConfiguration where Description like '%Cisco%' and IPEnabled='True'"

If ($args[0])
{
    $tsPackageID = $args[0]
    $tsPackageID = "$tsPackageID"
}
ELSE
{
    OnError "ERROR: Please provide a package ID to execute (ex. RunTS.ps1 ABC123456)"
}

If (TestSiteConnection)
{
    Write-Host "Ensuring SCCM Client Services is running..."
    $ccmService = Get-Service ccmexec
    If ($ccmService.Status -ne "Running")
    {
        Start-Service ccmexec
        Start-Sleep -s 120
    }
    
    Write-Host "Connecting to SCCM Client ComObject..."
    try 
    {
        $UI = New-Object -ComObject "UIResource.UIResourceMgr" -ErrorAction Stop
    }
    catch 
    {
        OnError "ERROR: Unable to create SCCM Client COM object"
    }
    
    Write-Host "Getting list of available applications..."
    $availableApps = $UI.GetAvailableApplications() | Select-Object PackageId, PackageName
    If ($availableApps)
    {
        ForEach ($_ IN $availableApps)
        {
            If ($_.PackageId -eq $tsPackageID)
            {
                Try
                {
                    Write-Host "Starting installation of $tsPackageID..."
                    $UI.ExecuteProgram($programID, $tsPackageID, $true)
                    Start-Process -FilePath "C:\Windows\System32\schtasks.exe" -ArgumentList "/DELETE","/TN ""$schTaskName""","/F" -Wait -ErrorAction SilentlyContinue
                    break
                }
                Catch
                {
                    Write-Host "Error: Failed to execute $tsPackageID. Will be retried on next logon."
                    break
                }
            }
        }
    }
    ELSE
    {
        OnError "ERROR: Unable to get list of available applications"
    }
}
ELSE
{
    OnError "WARNING: VPN or external network connection detected. No additional action will be taken at this time."
}
Stop-Transcript




