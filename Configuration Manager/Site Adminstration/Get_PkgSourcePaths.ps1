Import-Module ActiveDirectory
Import-Module "$env:SMS_ADMIN_UI_PATH\..\configurationmanager.psd1"

$outFile = "C:\Temp\PkgSources_$(Get-Date -uformat '%m-%d-%y-%I-%M').csv"

$siteCode = $(Get-WMIObject -ComputerName "$env:ComputerName" -Namespace "root\sms" -class "SMS_ProviderLocation" -ErrorAction SilentlyContinue).SiteCode 

If (!($siteCode))
{
   # $siteCode = $([WmiClass]"\\localhost\ROOT\ccm:SMS_Client").GetAssignedSite()
    $siteCode = (Get-ItemProperty -Path "HKLM:SOFTWARE\Microsoft\SMS\Mobile Client").AssignedSiteCode
}

Set-Location "$($siteCode):"

$getApps = Get-CMApplication

ForEach($app in $getApps){
    $appMgmt = ([xml]$app.SDMPackageXML).AppMgmtDigest
    $appName = $appMgmt.Application.Displayinfo.FirstChild.Title

    ForEach($dt in $appMgmt.DeploymentType){
        $appData = @{
            AppName = $appName
            DeploymentTypeName = $dt.Title.InnerText
            Source = $dt.Installer.Contents.Content.Location
        }

        $object = New-Object PSObject -Property $appData

        $Object | Select-Object AppName, DeploymentTypeName, Source | Export-CSV $outFile -NoTypeInformation -Encoding UTF8 -Append -Force
    }
}

$testSources = Import-CSV "C:\Temp\AppSources_04-03-19-04-09.csv"

ForEach($_ in $testSources)
{
    $isValid = $false
    If(Test-Path "$($_.Source)")
    {
        $isValid = $true
    }

    $testResults = @{
        DeploymentTypeName = $_.DeploymentTypeName
        Source = $_.Source
        SourceValid = $isValid
    }

    $newObject = New-Object PSObject -Property $testResults

    $newObject | Select-Object DeploymentTypeName, Source, SourceValid | Export-CSV "C:\Temp\appsourcetest.csv" -NoTypeInformation -Encoding UTF8 -Append
}


#$outFile = "C:\Temp\PkgSources_$(Get-Date -uformat '%m-%d-%y-%I-%M').csv"

$pkgList = Get-CMPackage | Select-Object PackageID, Name, PkgSourcePath, @{Name='SecuredScopeNames';Expression={[string]::join(";",($_.SecuredScopeNames))}}

$pkgList | Export-CSV $outFile -NoTypeInformation -Encoding UTF8 -Append -Force


$pkgSources = Import-CSV "C:\Temp\PkgSources_04-04-19-11-01.csv"

$outfile2 = "C:\Temp\pkgsourcetest_$(Get-Date -uformat '%m-%d-%y-%I-%M').csv"

ForEach($_ IN $pkgSources)
{
    $isValid = $false
    IF(!(Test-Path "$($_.PkgSourcePath)"))
    {
        Get-ChildItem "$($_.PkgSourcePath)"
        If($Error[0].Exception -is [System.UnauthorizedAccessException])
        {
            $isValid = $true
        }
    }
    Else{
        $isValid = $true
    }

    $testres = @{
        PackageID = $_.PackageID
        Name = $_.Name
        SourceValid = $isValid
        SourcePath = $_.$PkgSourcePath
    }
    
    $object2 = New-Object PSObject -Property $testres

    $object2 | Export-CSV $outfile2 -NoTypeInformation -Encoding UTF8 -Append
}