# File format: Publisher, AppName, Version, SourcePath, InstallCommand

Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\Console\bin\ConfigurationManager.psd1"

$SCCMSiteCode = "MySiteCode"
$CMSitePath = $SCCMSiteCode+ ":"
$distPointGroupName = "Distribution Point Group Name"
$iconPath = "C:\Windows\System32\shell32.dll"
$detectionScriptType = "VBScript"

Set-Location $CMSitePath

$getApplicationInfo = Get-Content $PSScriptRoot\Applications.txt

ForEach ($app in $getApplicationInfo)
{
   
    $splitLine = $app.Split(",")
    $appPublisher = $splitLine[0]
    $appName =$splitLine[1]
    $appVersion = $splitLine[2]
    $appSource = $splitLine[3]
    $appCommand = $splitLine[4]
    $depploymentTypeName = "Install " + $appPublisher + " " + $appName + " " + $appVersion
    
    $localDescription = "Install $appPublisher $appName version $appVersion. A reboot is required."

    Write-Host "Attempting to creating Application: $appName"
    Write-Host "Deployment Type Name: $depploymentTypeName"
    Write-Host "Content location: $appSource"

    
    If (Get-CMApplication -Name $appName)
    {
        Write-Host "WARNING: Application name aleady exists."
    }
    Else
    {
        Try
        {
            New-CMApplication -Name $appNAme -LocalizedApplicationDescription $localDescription -LocalizedApplicationName $appName -Publisher $appPublisher -SoftwareVersion $appVersion
            Add-CMDeploymentType -ApplicationName $appName -DeploymentTypeName $depploymentTypeName -DetectDeploymentTypeByCustomScript -InstallationProgram $appCommand -ScriptContent "Place Holder" -ScriptInstaller -ScriptType VBScript -ContentLocation $appSource -InstallationBehaviorType InstallForSystem -InstallationProgramVisibility Hidden -LogonRequirement WhetherOrNotUserLoggedOn -MaximumAllowedRunTimeMinutes 15
        }
        Catch
        {
            Write-Host "WARNING: Error encountered during Application creation: " + $error[0]
        }
    }
}

Set-Location C: