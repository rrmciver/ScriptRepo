Function ExitOnError($message, $code)
{
    Write-Host $message
    Stop-Transcript
    EXIT $code
}

Clear-Host

Start-Transcript -Path "C:\Windows\Temp\ExtractIndexFromWIM.log"

$Env:Path = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM;C:\Windows\System32'

Import-Module "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.psd1" -ErrorAction SilentlyContinue

$sourcePath = Read-Host "Enter file name and path to source .wim file"

If (!(Test-Path $sourcePath))
{
    ExitOnError "WARN: Unable to read image file or invalid path"
}

$destPath = Read-Host "Enter path for destination .wim"

If ($destpath -like "*.wim*")
{
    ExitOnError "WARN: Do not include the file name in the distination path"
}
ElseIf (!(Test-Path $destPath))
{
    ExitOnError "WARN: Unable to read destination path or folder does not exist"
}

$destName = Read-Host "Enter file name for destination .wim"
If (!($destName -like "*.wim"))
{
    ExitOnError "WARN: Destination file name did not include the .wim extention"
}

try {
    Get-WindowsImage -ImagePath $sourcePath -ErrorAction Stop    
}
catch {
    ExitOnError $error[0] $LASTEXITCODE
}

$sourceIndex = Read-Host "Enter index number to extract"

try {
    Export-WindowsImage -SourceImagePath "$sourcePath" -SourceIndex $sourceIndex -DestinationImagePath "$destPath\$destName" -CheckIntegrity -CompressionType max
}
catch {
    ExitOnError $error[0] $LASTEXITCODE
}

Stop-Transcript