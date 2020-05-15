#Requres -Version 5.0
#
# Name: SSL Analyzer Tool
#
# Description: Pulls a list of urls from a text file and runs them through a pair of publicly avaialble SSL scanners. A list of urls with each scan grade is exported to a csv file in the script's execution directory. 
# Detailed information for each is exported to seperate JSON files into the "Details" folder.
# As of last update the following SSL scanners are used:
# 
# - Mozilla Obervatory
# - SSL Labs
#

Function MozillaObservatory($uri)
{
    # Mozilla Observatory
    Write-Host "Scanning $uri with Mozilla Obersvatory..."
    Try
    {
        $analyzeRequest = 'https://http-observatory.security.mozilla.org/api/v1/analyze?host=' + $uri + '&hidden=true&rescan=true'
        $getAnalysis = Invoke-WebRequest $analyzeRequest -Method POST | ConvertFrom-JSON
        While ($getAnalysis.state -eq "RUNNING" -OR $getAnalysis.state -eq "PENDING")
        {
            Write-Host "Analysis is still running. Waiting 10 seconds then refreshing..."
            Start-Sleep 10
            $getAnalysis = Invoke-WebRequest $analyzeRequest -Method GET | ConvertFrom-JSON
        }

         If ($getAnalysis.state -eq "FAILED" -OR $getAnalysis.state -eq "ABORTED")
         {
            Write-Host "WARNING: Analysis result: " $getAnalysis.state
            throw
         }
         ElseIf ($getAnalysis.error)
         {
            $result = $getAnalysis.error
         }
         Else
         {
            Write-Host "Analysis finished."
            $scanID = $getAnalysis.scan_id
            $grade = $getAnalysis.grade
            $result = @{}
            $result.Grade = $grade
            $result.ScanID = $scanID
         }
    }
    Catch
    {
        Write-Host "Error running SSL scan against $uri from the Mozilla Observatory"
        $result = "ERROR"
    }

    return $result
}

Function SSLLabs($uri)
{
    # SSL Labs
    Write-Host "Scanning $uri with SSL Labs..."
    Try
    {
        $analyzeRequest = 'https://api.ssllabs.com/api/v3/analyze?host=' + $uri + '&startNew=on&all=done'
        $getAnalysis = Invoke-WebRequest $analyzeRequest | ConvertFrom-JSON
        $statusRequest = 'https://api.ssllabs.com/api/v3/analyze?host=' + $uri + '&all=done'
        Do
        {
            Write-Host "Analysis is running. Waiting 10 seconds then refreshing..."
            Start-Sleep 10
            $getAnalysisStatus = Invoke-WebRequest $statusRequest | ConvertFrom-JSON
        }
        Until ($getAnalysisStatus.status -eq "READY" -OR $getAnalysisStatus.status -eq "ERROR")
        
        If ($getAnalysisStatus.status -eq "ERROR")
        {
            Write-Host "WARNING: Analysis returned error: " $getAnalysisStatus.statusMessage
            $result = $getAnalysisStatus.statusMessage
            throw
        }
        Else
        {
            Write-Host "Analysis finished."
            $result = $getAnalysisStatus.endpoints
        }
     }
     Catch
     {
        Write-Host "Erorr running SSL scan for $server from SSL Labs"
     }
     
     return $result
}


Start-Transcript "$PSScriptRoot\SSLAnalyzer.log"

$serverListFile = "$psscriptroot\urilist.txt"

Write-Host "Initializing results file..."
$resultsFile = "$PSScriptRoot\SSLAnalyzerToolResults.csv"
$detailsFilePath = "$PSScriptRoot\Details"

Try
{
    If (Test-Path $resultsFile)
    {
        Write-Host "Existing results file found. Deleting..."
        Try
        {
            Remove-Item $resultsFile -Force
        }
        Catch
        {
            Write-Host "ERROR: Unable to delete existing results file."
            throw
        }
    }

    Try
    {
        New-Item $resultsFile -ItemType File | Out-Null
        "Tested URL,Server Name,Grade,Scanner Used" | Out-File $resultsFile
    }
    Catch
    {
        Write-Host "ERROR: Unable to create results file. Script will now exit."
        throw
    }

    If (!(Test-Path $detailsFilePath))
    {
        Try
        {
            New-Item $detailsFilePath -ItemType "directory" | Out-Null
        }
        Catch
        {
            Write-Host "ERROR: Unable to create Details directory in script root directory. Script will now exit."
            throw
        }
    }

    #Get list of addresses to test
    Write-Host "Importing url list..."
    $serverList = Get-Content $serverListFile
    ForEach ($server in $serverList)
    {
        Write-Host "Starting SSL analysis for $server"
        $mozillaScan = MozillaObservatory($server)
        If ($mozillaScan.count -gt 1)
        {
            $grade = $mozillaScan.Grade
            $iD = $mozillaScan.ScanID
            Write-Host "Exporting Mozilla Oberservatory results for $server"
            "$server,NA,$grade,Mozilla Observatory" | Out-File $resultsFile -Append
            $detailRequest = 'https://http-observatory.security.mozilla.org/api/v1/getScanResults?scan=' + $iD
            $getDetailedReport = Invoke-WebRequest $detailRequest -Method GET | ConvertFrom-JSON | ConvertTo-JSON | Out-File "$detailsFilePath\$server Mozilla.json" -Encoding ascii -Force
        }
        Else
        {
            $error = $mozillaScan
            "$server,NA,$error,Mozilla Observatory" | Out-File $resultsFile -Append
        }
        
        $sslLabsScan = SSLLabs($server)
        If ($sslLabsScan.getType().name -eq "PSCustomObject")
        {
            ForEach ($endpoint in $sslLabsScan)
            {
                If (!($endpoint.ServerName))
                {
                    $serverName = $server
                }
                Else
                {
                    $serverName = $endpoint.ServerName
                }
                Write-Host "Exporting SSL Labs results for uri: $server endpoint: $serverName" 
                If (!($endpoint.grade))
                {
                    $grade = $endpoint.statusMessage
                }
                Else
                {
                    $grade = $endpoint.grade
                }
                $ipAddress = $endpoint.ipAddress
                "$server,$serverName,$grade,SSL Labs" | Out-File $resultsFile -Append
                $detailsRequest = 'https://api.ssllabs.com/api/v3/getEndpointData?host=' + $server + '&s=' + $ipAddress
                $getDetails = Invoke-WebRequest $detailsRequest | ConvertFrom-JSON | ConvertTo-JSON | Out-File "$detailsFilePath\$serverName SSLLabs.json" -Encoding ascii -Force
            }
        
        }
        Else
        {
            "$server,$serverName,$sslLabsScan,SSL Labs" | Out-File $resultsFile -Append
        }
    }
    Write-Host "All analyses finished." 
}
Catch
{
    Write-Host "ERROR: Script execution failure"
}
Finally
{
    Stop-Transcript
}    
    

    

    

