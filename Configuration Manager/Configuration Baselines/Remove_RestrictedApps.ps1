Start-Transcript -Path "C:\Windows\Temp\ApplicationEnforcement.log" -force -append

$fileNames = @("PUTTY.EXE", "PUTTYGEN.EXE")
$msiDisplayNames = @("PuTTY")
$foundGUIDs = @()

$getInstalledAppsX86 = Get-ItemProperty HKLM:\Software\WOW6432NODE\Microsoft\Windows\CurrentVersion\Uninstall\* |  Select-Object DisplayName, PSChildName

$getInstalledAppsX64 = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |  Select-Object DisplayName, PSChildName

ForEach ($name in $msiDisplayNames)
{
    $findDisplayNamex86 = $getInstalledAppsX86 | Where-Object DisplayName -like "*$name*"
    If ($findDisplayNamex86)
    {
        Write-Host "Matching display name found in 32-bit registry: " $findDisplayNamex86.DisplayName $findDisplayNamex86.PSChildName
        $foundGUIDs += $findDisplayNamex86.PSChildName
    }

    $findDisplayNamex64 = $getInstalledAppsx64 | Where-Object DisplayName -like "*$name*"
    If ($findDisplayNamex64)
    {
        Write-Host "Matching display name found in 64-bit registry: " $findDisplayNamex64.DisplayName $findDisplayNamex64.PSChildName
        $foundGUIDs += $findDisplayNamex64.PSChildName
    }
}

ForEach ($GUID in $foundGUIDs)
{
    Write-Host "Attemping uninstall: $GUID"
    $process = Start-Process -FilePath "$env:systemroot\system32\msiexec.exe" -ArgumentList "/x $GUID /qn /norestart" -PassThru -Wait
    Write-Host "Result: " $process.ExitCode
}

$driveIndex = Get-ChildItem -Path C:\ -Recurse -ErrorAction SilentlyContinue -Force

ForEach ($file in $fileNames)
{
    $getFiles = $driveIndex | Where-Object Name -eq $file

    If ($getFiles)
    {
        ForEach ($file in $getFiles)
        {
            $filePath = $file.FullName
            Write-Host "Deleting file: $filePath"
            Remove-Item -Path $filePath -force
        }
    }
}
Stop-Transcript