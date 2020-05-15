$appList = @()

$get32BitApps = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |  Select-Object DisplayName, DisplayVersion, Publisher, InstallDate

$get64BitApps = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate

ForEach ($_ in $get32BitApps)
{
    $appList += [PSCustomObject]@{
        DisplayName = $_.DisplayName
        DisplayVersion = $_.DisplayVersion
        Publisher = $_.Publisher
        InstallDate = $_.InstallDate
    }
}

ForEach ($_ in $get64BitApps)
{
    $appList += [PSCustomObject]@{
        DisplayName = $_.DisplayName
        DisplayVersion = $_.DisplayVersion
        Publisher = $_.Publisher
        InstallDate = $_.InstallDate
    }
}

$appList | Sort-Object DisplayName | Format-Table -AutoSize