# File format: Manufacturer, Name, Version, SourcePath

Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\Console\bin\ConfigurationManager.psd1"

$SCCMSiteCode = "MySiteCode"
$CMSitePath = $SCCMSiteCode+ ":"

Set-Location $CMSitePath

$distPointGroupName = "Distribution Point Group Name"

$getPackageInfo = Get-Content $PSScriptRoot\PackageNames.txt

ForEach ($pkg in $getPackageInfo)
{
    $splitPackage = $pkg.Split(",") 
    $pkgManufacturer = $splitPackage[0]
    $pkgName = $splitPackage[1]
    $pkgVersion = $splitPackage[2]
    $pkgSource = $splitPackage[3]
    
    Write-Host "New package Name: $pkgName"
    Write-Host "Manufacturer: $pkgManufacturer"
    Write-Host "Version: $pkgVersion"
    Write-Host "Source location: $pkgSource"
    
    If (Get-CMPackage -Name $pkgName | Where-Object {$_.Version -eq $pkgVersion})
    {
        Write-Host "WARNING: A package with this name and version already exists."
    }
    Else
    {
        Try
        {
            New-CMPackage -Name $pkgName -Manufacturer $pkgManufacturer -Path $pkgSource -Version $pkgVersion
            Start-CMContentDistribution -PackageName $pkgName -DistributionPointGroupName $distPointGroupName
        }
        Catch
        {
            Write-Host "Creation of package $pkgName failed: $error[0]"
        }
    }
    
}

Set-Location C: