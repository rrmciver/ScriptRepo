Function OnError ($exitCode)
{
    Stop-Transcript
    EXIT $exitCode
}

$backupTimeStamp = Get-Date -format yyyyMMddhhmm
$backupPath = "D:\Backups\TaskSequenceBackup\$backupTimeStamp"
$logPath = "C:\Windows\Temp\BackupTaskSequences.log"

Start-Transcript -Path $logPath -Append -Force

Try
{
    Import-Module "$env:SMS_ADMIN_UI_PATH\..\configurationmanager.psd1" -ErrorAction Stop
    $siteCode = $(Get-WMIObject -ComputerName "$ENV:ComputerName" -NameSpace "root\sms" -Class "SMS_ProviderLocation").SiteCode
    new-psdrive -Name $SiteCode -PSProvider "AdminUI.PS.Provider\CMSite" -Root "$ENV:ComputerName" -Description "SCCM Site" -ErrorAction Stop | Out-Null 
    Set-Location "$($siteCode):" -ErrorAction Stop
    New-Item -Path "$backupPath" -ItemType "directory" -ErrorAction Stop | Out-Null
    $taskSequences = Get-CMTaskSequence
}
Catch {
    OnError $LASTEXITCODE
}

ForEach ($_ IN $taskSequences)
{
    $packageID = $_.PackageID
    $tsName = $_.Name
    "Exporting $($packageID) to $($backupPath)..."
    Export-CMTaskSequence -TaskSequencePackageID $packageID -ExportFilePath "$backupPath\$tsName ($packageID).zip" -force
    "Done."
}

Set-Location C:
Stop-Transcript