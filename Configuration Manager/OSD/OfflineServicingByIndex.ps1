Function ExitOnError($message, $code)
{
    Write-Host $message
    Stop-Transcript
    EXIT $code
}

Clear-Host

Start-Transcript -Path "C:\Windows\Temp\OffliceServicingByIndex.log"

$Env:Path = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM;C:\Windows\System32'

Import-Module "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.psd1" -ErrorAction SilentlyContinue

$wimPath = Read-Host "Enter file name and path to .wim file"

If (!(Test-Path $wimPath))
{
    ExitOnError "WARNING: Unable to read image file or invalid path"
}

$mountPath = Read-Host "Enter path to mount directory"

If (!(Test-Path $mountPath))
{
    try {
        New-Item -ItemType "directory" -Path $mountPath -ErrorAction Stop
    }
    catch {
        ExitOnError "ERROR: Unable to create mount directory ($mountPath)" $LASTEXITCODE
    }
}

$packagePath = Read-Host "Enter path to update source directory"

If (!(Test-Path $packagePath))
{
    ExitOnError "WARNING: Unable to read update source directory ($packagePath)" $LASTEXITCODE
}

try {
    Get-WindowsImage -ImagePath $wimPath -ErrorAction Stop    
}
catch {
    ExitOnError $error[0] $LASTEXITCODE
}

$mountIndex = Read-Host "Enter index number to service"

try {
    Mount-WindowsImage -ImagePath $wimPath -Index $mountIndex -Path $mountPath -ErrorAction Stop
}
catch {
    ExitOnError $error[0] $LASTEXITCODE
}

Add-WindowsPackage -Path $mountPath -PackagePath $packagePath -LogPath "C:\Windows\Temp\OffliceServicingByIndex_AddPackage.log"
Dismount-WindowsImage -Path $mountPath -Save -LogPath "C:\Windows\Temp\OffliceServicingByIndex_Unmount.log"

Stop-Transcript