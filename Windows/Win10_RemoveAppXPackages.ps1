Start-Transcript "$env:Temp\RemoveAppXPackages.log" -Append -Force
$keepApps = "Microsoft.WindowsCalculator", "Microsoft.Appconnector", "Microsoft.WindowsSoundRecorder", "Microsoft.DesktopAppInstaller", "Microsoft.MicrosoftStickyNotes", "Microsoft.Windows.Photos"
$provPackages = Get-AppxProvisionedPackage -online | Select-Object DisplayName, PackageName | Sort-Object DisplayName
$appxPackages = Get-AppxPackage -PackageTypeFilter Bundle | Select-Object Name, PackageFullName | Sort-Object Name

If ($provPackages)
{
    ForEach ($app in $provPackages)
    {
        If ($app.DisplayName -in $keepApps)
        {
            Write-Host "Skipping removal of provisioned package: $($app.DisplayName)"
        }
        else {
            Write-Host "Attempting removal of provisioned package: $($app.DisplayName)"
            try {
                Remove-AppxProvisionedPackage -PackageName $app.PackageName -online -allusers -ErrorAction Stop
            }
            catch {
                Write-Host $Error[0]
            }
        }
    }
}

If ($appxPackages) {
    ForEach ($app in $appxPackages) {
        If ($app.Name -in $keepApps) {
            Write-Host "Skipping removal of Appx package: $($app.Name)"
        }
        else {
            Write-Host "Attempting removal of Appx package: $($app.Name)"
            try {
                Remove-AppxPackage -Package $app.PackageFullName -allusers -ErrorAction Stop
            }
            catch {
                Write-Host $Error[0]
            }
        }
    }
}
Stop-Transcript