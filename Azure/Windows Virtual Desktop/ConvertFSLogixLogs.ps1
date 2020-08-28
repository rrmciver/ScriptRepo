<#
.SYNOPSIS
    Convert FSLogix Agent logs on session hosts to UTF8 encoded copies
.DESCRIPTION
    This script is used to create UTF8 encoded copies of the FSLogix agent logs to enable support for ingestion into Log Analytics via Custom Logs
.NOTES
    Script is offered as-is with no warranty, expressed or implied.
    Author: Richard McIver
    Last Modified: 8/28/2020
#>

Start-Transcript "$env:Temp\ConvertFSLogixLogs.log" -force

# FSLogix default log file location
$fslogixLogPath = "C:\ProgramData\FSLogix\Logs"
Write-Host "Using FSLogix log file path: $fslogixLogPath"

# Log folder containing files for Log Analytics ingestion
$laIngestPaths = @()
$laIngestPaths += $fsLogixLogPath + "\Profile"
$laIngestPaths += $fsLogixLogPath + "\CloudCacheProvider"
$laIngestPaths += $fsLogixLogPath + "\CloudCacheService"

ForEach ($path in $laIngestPaths)
{
    Write-Host "Starting conversion tasks on log files in: $path"
    If(!(Test-Path $path)){
        Continue
    }
    $fileList = Get-ChildItem $path

    ForEach($file in $fileList)
    {
        $shortFileName = (($file.Name).Split("."))[0]
        If($shortFileName -like "*utf8*")
        {
            Continue
        }
        Else
        {
            $utf8FileName = $shortFileName+"_utf8.log"
        }
        
    
        If($utf8FileName -in $fileList.Name)
        {
            # See if the source log has new content since last run
            Try{
                $contSourceLog = Get-Content -Path "$path\$($file.Name)"
                $contDestLog = Get-Content -Path "$path\$utf8FileName"
                $newContent = (Compare-Object $contSourceLog $contDestLog).InputObject
                If ($newContent)
                {
                    Write-Host "Appending new UTF8 content from $($file.Name) to $utf8FileName"
                    Add-Content -Path "$path\$utf8FileName" -Value $newContent
                }
            }
            Catch{
                $_
            }
        }
        Else
        {
            # Create UTF8 copy of the log file to allow for Log Analytics ingestion
            Try{
                Write-Host "Creating UTF8 encoded copy of $($file.Name) for LA ingestion"
                Get-Content "$path\$($file.Name)" | Set-Content "$path\$utf8FileName"
            }
            Catch{
                $_
            }
        }
    }
}

Stop-Transcript