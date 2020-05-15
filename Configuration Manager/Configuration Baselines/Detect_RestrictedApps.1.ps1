$fileNames = @("PUTTY.EXE", "PUTTYGEN.EXE")
$msiDisplayNames = @("PuTTY")
$isDetected = "False"

$getInstalledAppsX86 = Get-ItemProperty HKLM:\Software\WOW6432NODE\Microsoft\Windows\CurrentVersion\Uninstall\* |  Select-Object DisplayName, PSChildName

$getInstalledAppsX64 = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |  Select-Object DisplayName, PSChildName

ForEach ($name in $msiDisplayNames)
{
    $findDisplayNamex86 = $getInstalledAppsX86 | Where-Object DisplayName -like "*$name*"
    If ($findDisplayNamex86)
    {
        $isDetected = "True"
    }
    Else 
    {
        $findDisplayNamex64 = $getInstalledAppsx64 | Where-Object DisplayName -like "*$name*"
        If ($findDisplayNamex64)
        {
            $isDetected = "True"
        }
    } 
}

ForEach ($file in $fileNames)
{
    $getFile = Get-ChildItem -Path C:\ -Filter $file -Recurse -ErrorAction SilentlyContinue -Force
    If ($getFile)
    {
        $isDetected = "True"
        break
    }
}

Write-Host $isDetected

