#
# Application Push Tool (APT)
# Version 2.0
# Change log:
#
# v1.1 - Added logic to subscripts for better logging and error tracking.
# v1.2 - Added current date to the end of the result log file. Also added aptVer variable for better version tracking.
# v2.0 - Rewrote script to use functions to reduce reduntant code, incresed detail of on-screen information, and added code to automatically pipe script execution details to a log file.
#
#
# Instructions:
# 
# 1. Ensure psexec.exe exists in the script's execution directory. (https://docs.microsoft.com/en-us/sysinternals/downloads/psexec)
# 
# 2. Set $exePath to the content source path of the application you wish to deploy.
#
# 3. Set $exeName to the name of the executable to be run on each machine to install the application.
#
# 4. Create a list of computer names to deploy the application to. Recommend creating the list in excel and saving as a .csv file.
#
# 5. Set $listPath to the location and file name of the list of computer names you wish to import.
# 
# 6. Run APT2.ps1 and follow the on-screen prompts to begin deployment.


# Initializing global variables
$aptVer = "2.0"
#
Function LogWrite
{
   Param ([string]$logstring)
   $logTimeStamp = Get-Date -uFormat "%m-%d-%Y-%H:%M:%S"
   Add-content $strLogFile -value "$logTimeStamp - $logstring"
}

Function ResultWrite ($compName, $resString)
{
    LogWrite "Writing $compName, $resString to $strResults"
    Write-Output "$compName, $resString" | out-file $strResults -append
}

Function PSWait ($prcList)
{
    $prcCount = $prcList.Count
    LogWrite "Found $prcCount running PowerShell processes"
    while ($prcList.count -ge $maxProc)
    {
        LogWrite "WARNING: Maximum number ($maxProc) of concurrent sessions reached. Waiting $waitTime seconds before continuing."
        Write-Host "Maximum number ($maxProc) of concurrent sessions reached. Waiting $waitTime seconds before continuing." 
        Start-Sleep -s $waitTime
        LogWrite "Getting updated list of running processes..."
        $prcList = Get-Process 'Powershell' -ErrorAction SilentlyContinue
    }
}

Function TestNet ($compName)
{
    LogWrite "Beginning network connectivity test..."
    Write-Host "Beginning network connectivity test..."
    $testRes = $NULL
    If (Test-Connection -ComputerName "$compName" -count 2 -Quiet -ErrorAction SilentlyContinue)
    {
        LogWrite "Test successful. $compName is online."
        Write-Host "Test successful. $compName is online."
        $testRes = "Success"
    }
    Else
    {
        LogWrite "ERROR: Test failed. $compName appears to be offline. Checking DNS...."
        Write-Host "ERROR: $compName appears to be offline. Attempting DNS lookup..."
        If (Resolve-DNSName "$compName" -ErrorAction SilentlyContinue)
        {
            LogWrite "ERROR: DNS lookup successful. $compName is offline."
            Write-Host "DNS lookup successful for $compName. Computer is offline."
            $testRes = "Offline"
        }
        Else
        {
            LogWrite "ERROR: DNS lookup failed. $compName may be offline or there are issues with its DNS records."
            Write-Host "DNS lookup failed for $compName."
            $testRes = "DNS Lookup Fail"
        }
      
    }

    Return $testRes
}

Function TestADM ($compName)
{
    LogWrite "Beginning admin share connectivity test..."
    Write-Host "Beginning admin share connectivity test..."
    $testRes = $NULL
    $admPath = "\\$compName\c$"
    LogWrite "Attempting to connect to $admPath"
    Write-Host "Attempting to connect to $admPath"
    If (Test-Path $admPath)
    {
        LogWrite "Connection to $admPath successful."
        Write-Host "Successfully connected to $admPath"
        $testRes = "Success"
    }
    Else
    {
        LogWrite "WARNING: Connection to $admPath failed. Attempting to start the winrm service on $compName and try again."
        Write-Host "WARNING: Connection to $admPath failed. Attempting to start the winrm service on $compName and try again."
        cmd.exe /c "$psexePath \\$compName net start winrm" -ErrorAction SilentlyContinue
        If (Test-Path $admPath)
        {
            LogWrite "Connection to $admPath successful after winrm service start."
            Write-Host "Connection to $admPath successful after winrm service start."
            $testRes = "Success"
        }
        Else
        {
            LogWrite "ERROR: Connection to $admPath failed again after winrm service start. There may be local firewall or permissions issues preventing the connection."
            Write-Host "ERROR: Could not connect to $admPath"
            $testRes = "Could not connect to $admPath"
        }
    }

    Return $testRes
}

Function CopyPackage ($compName)
{
    LogWrite "Beginning package copy to destination computer..."
    Write-Host "Beginning package copy to destination computer..."
    $isStatus = $NULL
    $dstPath = "\\$compName\c$\OTSAPT2"
    LogWrite "Checking for existance of $dstPath..."
    Write-Host "Checking for existance of $dstPath..."
    if (!(Test-Path "$dstPath"))
    {
        LogWrite "$dstPath does not exist. Creating..."
        Write-Host "$dstPath does not exist. Creating..."
        New-Item $dstPath -type directory | Out-Null
    }

    If (Test-Path "$dstPath")
    {
       LogWrite "$dstPath exists. Generating random folder name for working directory..."
       Write-Host "$dstPath exists. Generating random folder name for working directory..."
       Do
        {
            $rndFolder = -join ((65..90) + (97..122) | Get-Random -Count 8 | % {[char]$_})
            LogWrite "Trying: $rndFolder"
        }
        Until(!(Test-Path "$dstPath\$rndFolder"))

        $rndPath = "$dstPath\$rndFolder"
        LogWrite "$rndFolder is unique. Creating folder..."
        Write-Host "$rndFolder is unique. Creating folder..."
        
        New-Item $rndPath -type directory | Out-Null

        LogWrite "Testing if $rndPath was created successfully..."
        Write-Host "Testing if $rndPath was created successfully..."
        If (Test-Path $rndPath)
        {
            LogWrite "$rndPath exists. Beginning copy of $exePath..."
            Write-Host "$rndPath exists. Beginning copy of $exePath..."
            Copy-Item $exePath\* $rndPath -Recurse -Force | Out-Null
            LogWrite "Testing if copy was successful..."
            Write-Host "Testing if copy was successful..."
            If (Test-Path "$rndPath\$exeName")
            {
                LogWrite "$exeName was found in $rndPath. Package copy was successful."
                Write-Host "$exeName was found in $rndPath. Package copy was successful."
                $isStatus = $rndFolder
            } 
            Else
            {
                LogWrite "ERROR: $exeName was not found in $rndPath. Package copy failed."
                Write-Host "ERROR: Copy of package source content to $rndPath was not successful"
                $isStatus = "Package Copy Failed"
                Remove-Item $dstPath -Force -Recurse | Out-Null
            }
        }
        Else
        {
            LogWrite "ERROR: $rndPath could not be created on destination computer."
            Write-Host "ERROR: $rndPath could not be created on destination computer"
            $isStatus = "Create Rnd Dest Failed"
            Remove-Item $dstPath -Force -Recurse | Out-Null
        }

    }
    Else
    {
        LogWrite "ERROR: $destPath could not be created on destination computer."
        Write-Host "ERROR: Destination path does not exist and could not be created."
        $isStatus = "Create Dest Failed"
    }

    Return $isStatus
}

Function CreateScratch ($compName)
{
    LogWrite "Creating scratch file..."
    Write-Host "Creating scratch file..."
    $isStatus = $NULL
    $scrFileName = "$scratchSpce\$compName.txt"
    LogWrite "Creating $scrFileName..."
    Write-Host "Creating $scrFileName..."
    New-Item $scrFileName -type file | Out-Null
    LogWrite "Testing to ensure $scrFileName was created successfully..."
    Write-Host "Testing to ensure $scrFileName was created successfully..."
    If (Test-Path $scrFileName)
    {
        LogWrite "$scrFileName was created successfully."
        Write-Host "Scratch file $scrFileName created successfully"
        $isStatus = $scrFileName
    }
    Else
    {
        LogWrite "ERROR: $scrFileName could not be created."
        Write-Host "ERROR: Could not create scratch file."
        $isStatus = "Create SCR Failed"
    }
    
    Return $isStatus
}

Function WriteScratch ($compName, $rndFolder, $scrFile)
{
    LogWrite "Writting execution code to $scrFile..."
    Write-Host "Writting execution code to $scrFile..."
    $dstPath = "\\$compName\c$\OTSAPT2"
    $lclPath = "C:\OTSAPT2"
    LogWrite "Testing executable extension for known file types and writing execution command appropriately..."
    If ($exeExt -eq "vbs")
    {
        LogWrite "$exeName is a vbscript."
        LogWrite "Writting command: cmd.exe /c '$psexePath \\$compName cscript.exe //b //nologo $lclPath\$rndFolder\$exeName'"
        Write-Output "cmd.exe /c ""$psexePath"" \\$compName cscript.exe //b //nologo $lclPath\$rndFolder\$exeName" | Out-file $scrFile -Append | Out-Null
    }
    ElseIf ($exeExt -eq "ps1")
    {
         LogWrite "$exeName is a PowerShell script."
         LogWrite "Writting command: cmd.exe /c '$psexePath \\$compName cmd.exe /c echo . | powershell -executionpolicy bypass -file $lclPath\$rndFolder\$exeName'"
         Write-Output "cmd.exe /c '$psexePath \\$compName cmd.exe /c echo . | powershell -executionpolicy bypass -file $lclPath\$rndFolder\$exeName'" | Out-file $scrFile -Append | Out-Null
    }
    ElseIf ($exeExt -eq "msi")
    {
         LogWrite "$exeName is a Microsoft Installer."
         LogWrite "Writting command: cmd.exe /c '$psexePath \\$compName msiexec /i /qn $lclPath\$rndFolder\$exeName'"
         Write-Output "cmd.exe /c '$psexePath \\$compName msiexec /i /qn $lclPath\$rndFolder\$exeName'" | Out-file $scrFile -Append | Out-Null
    }
    Else
    {
        LogWrite "$exeName is not a file type that is known to require a special command."
        LogWrite "Writting command: cmd.exe /c '$psexePath \\$compName $lclPath\$rndFolder\$exeName'"
        Write-Output "cmd.exe /c '$psexePath \\$compName $lclPath\$rndFolder\$exeName'" | Out-file $scrFile -Append | Out-Null
    }
    LogWrite "Writting commands to get the exit code of the executable."
    Write-Output 'if ($LastExitCode -eq 0) {$outTxt = "Success"}' | Out-File $scrFile -Append | Out-Null
    Write-Output 'else {$outTxt = "$LastExitCode"}' | Out-File $scrFile -Append | Out-Null
    LogWrite "Writting command to delete $destPath after execution is complete."       
    Write-Output "Remove-Item $dstPath -Force -Recurse" | Out-File $scrFile -Append | Out-Null                  
    # Set variables used to create new variables within the subscript. 
    $varStr1 = '$outTxt"'
    $varStr2 = '"'
    # Write logging command to scratch file. Will write the execution status for this computer to the log file when finished.
    LogWrite "Writting command to append computer name and execution status to $strResults"
    Write-Output "Write-Output $varStr2$compName, $varStr1 | out-file $strResults -append" | Out-File $scrFile -Append | Out-Null
    # Rename the scratch file to .ps1 so it can be called as a PS script.  
    LogWrite "Renaming the scratch file to .ps1 so it can be executed as a PowerShell script."              
    Rename-Item $scrFile "$compName.ps1"
    Write-Host "Writting complete."
}

$getDate = Get-Date -uformat "%m-%d-%Y"
$getLogStamp = Get-Date -uformat "%m-%d-%Y-%H-%M-%S"
$strLogFile = "$PSScriptRoot\OTS_APTExecutionLog$getLogStamp.log"
$strResults = "$PSScriptRoot\OTS_APTResults$getLogStamp.txt"

###########################################################################################################
###########################################################################################################
###########################################################################################################
###########################################################################################################
###########################################################################################################
###########################################################################################################

# Set path to psexec executable. Will be called to connect to target computer and run executable.
$psexePath = "$PSScriptRoot\psexec.exe"

# Set maximum number of asynchronous executions. If number of powershell process reaches or exceed this number, execution will pause and wait until the total drops below this threshold.
$maxProc = 11

#Set time to wait before re-checking the number of running processes.
$waitTime = 10

# Set path of the APT scratch space. This is where the sub-scripts that are called during execution will be created.
# This folder is deleted and recreated each time APT is run.
$scratchSpce = "$PSScriptRoot\Scratch"

LogWrite "Begin APT execution"
LogWrite "Application Push Tool (APT) Version $aptVer"
Clear-Host
Write-Host "Application Push Tool (APT)"
Write-Host "Version $aptVer"
Write-Host ""
Write-Host ""
Write-Host ""

# Set package source folder. All contents of this folder will be copied to the remote machine before executing.
$exePath = "\\softwarerepo\Software\Apps\SCCM\Client"
$exeName = "SCCMRepair-lite_silent.vbs"
# Set path and file name of csv file containing a list of computer names to target. This list will be imported and deployment attempted to each item. 
$listPath = $args[0]
If (!($listPath))
{
    $listPath = "$PSScriptRoot\sccm.csv"
}



LogWrite "Current package and executable hard set to $exePath and $exeName"
LogWrite "Prompting user if they want to continue with this package and executable or if they wish to change them..."
Write-Host "Current executable name and path:" 
Write-Host "$exePath\$exeName"
Write-Host ""
$strAns = Read-Host "Do you want to use this executable? (Y/N)"
Write-Host ""
If ($strAns -eq "N" -or $strAns -eq "n")
{
    LogWrite "User input a $strAns. Asking for new path and executable name..."
    Write-Host "Please enter the UNC path to the desired executable (Ex: \\softwarerepo\Software\Apps\SCCM\Client)"
    $exePath = Read-Host "Path"
    LogWrite "User entered: $exePath"
    Write-Host ""
    Write-Host "Please enter the name of desired executable or script in the previously entered path (Ex: SCCMClientRepair-lite.bat)"
    $exeName = Read-Host "File"
    LogWrite "User entered: $exeName"
}
ElseIf ($strAns -eq "Y" -or $strAns -eq "y")
{
    LogWrite "User input $strAns. Continuing with existing path and file."
    Write-Host "Using existing path and executable."
    Write-Host ""
}
Else
{
    LogWrite "User input an unknown response: $strAns. Defaulting to use the existing path and file."
    Write-Host "Input not 'Y' or 'N'. Using existing path and executable."
    Write-Host ""
}
$strAns = $NULL

LogWrite "Parsing $exeName to get file extension..."
$exeExt = $exeName.substring($exeName.length - 3, 3)
LogWrite "$exeName has an extension of $exeExt"


LogWrite "Current csv file with comptuer names to input is hard set to: $listPath."
LogWrite "Prompting user if they wish to continue with this csv file..."
Write-Host "Path and file name with computer names to target:" 
Write-Host "$listPath"
Write-Host ""
$strAns = Read-Host "Do you want to use this file? (Y/N)"
Write-Host ""
If ($strAns -eq "N" -or $strAns -eq "n")
{
    LogWrite "User input $strAns. Prompting user for new path and file name." 
    Write-Host "Please enter full (UNC) path to desired CSV file (Ex: $PSScriptRoot\ADSCCM.csv)"
    $listPath = Read-Host "Path"
    Write-Host ""
    LogWrite "User entered: $listPath"
}
ElseIf ($strAns -eq "Y" -or $strAns -eq "y")
{
    LogWrite "User input $strAns. Using existing csv file."
    Write-Host "Using existing csv file."
}
Else
{
    LogWrite "User input and unknown response: $strAns. Defaulting to use the existing file."
    Write-Host "Input not 'Y' or 'N'. Using existing csv file: $listPath."
}


# Verify package source location and executable is accessible. Based on $exePath and $exeName global variables. 
LogWrite "Testing to verify that $exePath and $exeName are accessible..."
Write-Host "Verifying package source content is accessible..."
Write-Host "Connecting to $exePath..."
Write-Host ""

If (Test-Path $exePath)
{
    LogWrite "Connection to $exePath successful."
    Write-Host "Success"
    Write-Host ""
    LogWrite "Verifying the $exeName is in $exePath"
    Write-Host "Checking for $exeName in $exePath"
    Write-Host ""
    If (Test-Path $exePath\$exeName)
    {
        LogWrite "$exeName was found in $exePath"
        Write-Host "Success"
        Write-Host ""
    }
    else
    {
        LogWrite "ERROR: $exeName was not found in $exePath"
        Write-Host "ERROR: Could not find $exePath\$exeName"
        Exit
    }
}
else
{
    LogWrite "ERROR: $exePath was not found."
    Write-Host "ERROR: Could not connect to package source $exePath"
    Exit
}

#Verify that csv file to import is accessible. Based on $listPath global variable. 
LogWrite "Verifing that $listPath is accessible..."
Write-Host "Verifying $listPath is accessible..."
Write-Host ""

if (Test-Path $listPath)
{
    LogWrite "$listPath was found."
    Write-Host "Success"
    Write-Host ""
}
else
{
    LogWrite "ERROR: $listPath was not found."
    Write-Host "ERROR: Could not find file $listPath"
    Write-Host ""
    Exit
}

# Creating the results file to track deployment status to each computer.
LogWrite "Creating $strResults to track the status of each machine targetted by APT..."
Write-Host "Creating results file $strResults..."
# Test if log file already exists. If yes, delete it.
if (Test-Path $strResults)
{
    LogWrite "WARNING: $strResults already exists. Deleting it..."
    Write-Host "$strResults already exists. Deleting and creating blank file."
    Remove-Item $strResults -Force
}

New-Item $strResults -type file | Out-Null

If (!(Test-Path $strResults))
{
    LogWrite "ERROR: $strResults was not able to be created."
    Write-Host "ERROR: Could not create $strResults."
    Write-Host "ERROR: $LastExitCode"
    Exit
}
Else
{
    LogWrite "$strResults created successfully. Writing column readers..."
    "Computer Name, Result" | Out-file -filepath $strResults
    LogWrite "Done."
    Write-Host "Results file created successfully."
    Write-Host ""
}

# Create the scratch folder for sub-scripts. Based on $scratchSpc global variable.
LogWrite "Creating scratch folder for temporary scripts: $scratchSpce" 
Write-Host "Creating scratch folder $scratchSpce..."

If (Test-Path $scratchSpce)
{
    LogWrite "WARNING: $scratchSpce already exists. Delete..."
    Write-Host "WARNING: $scratchSpce already exists. Deleting..."
    "Computer Name, Result" | Out-file -filepath $strResults
    Remove-Item $scratchSpce -force -Recurse
}

New-Item $scratchSpce -type directory | Out-Null
 
If(!(Test-Path $scratchSpce))
{
    LogWrite "ERROR: Scratch filder $scratchSpce could not be created."
    Write-Host "ERROR: Scratch folder could not be created."
    Exit
}
Else
{
    LogWrite "$scratchSpce created successfully."
    Write-Host "Scratch folder created successfully."
    Write-Host ""
}


# Import csv and begin processing list of comptuer names. 
LogWrite "Beginning import of $listPath..."
Write-Host "Importing list of computer names from $listPath..."
Write-Host ""
# Count number of rows in CSV to get total number of computers to be targetted by the deployment.
$getItemsSize = 0
$getItems = import-csv $listPath -Header Computer
LogWrite "Counting the number of computers found in $listPath..."
foreach ($_ in $getItems)
{
    $getItemsSize++
}
LogWrite "Found: $getItemsSize"
LogWrite "Displying deployment details to user and asking for confirmation to continue."
LogWrite "Executable path: $exePath"
LogWrite "Executable name: $exeName"
LogWrite "Number of computers: $getItemsSize"
LogWrite "First 10 computers:"
# Pause to display warning and deployment information for confirmation.
Clear-Host
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host "!!!!!!!!! WARNING - Deployment is about to begin !!!!!!!!!"
Write-Host ""
Write-Host "######### Please Review the Following Information Carefully Before Continuing #########"
Write-Host ""
Write-Host "Executable source path: $exePath"
Write-Host "Executable name: $exeName"
Write-Host "Number of computers targeted: $getItemsSize"
Write-Host "First 10 items from csv file:"
$smplList = 0
foreach ($_ in $getItems)
{
    $smplList++
    if ($smplList -le 10)
    {
        LogWrite $_.Computer
        Write-Host $_.Computer
    }
    else
    {
        break
    }
}
Write-Host ""

# Get confirmation that deployment info is accurate. If not, exit.
LogWrite "Prompting to confirm information is correct..."
$ruSure = Read-Host "Is this information correct? (Y/N)"
if ($ruSure -eq "Y" -or $ruSure -eq "y")
{
    LogWrite "User input $ruSure. Prompting again to confirm."
    Write-Host ""
    $ruSure = $NULL
    # Get second confirmation to begin deployment. If no, exit.
    $ruSure = Read-Host "Are you absolutely sure you want to proceed? (Y/N)"
    if ($ruSure -eq "Y" -or $ruSure -eq "y")
    {
        LogWrite "User input $ruSure. Beginning deployment..."
        Clear-Host
        Write-Host "Beginning deployment..."
        Write-Host ""
    }
    ElseIf ($ruSure -eq "N" -or $ruSure -eq "n")
    {
        LogWrite "User input $ruSure. Exiting."
        Write-Host "User does not wish to continue. Exiting APT..."
        Exit
    }
    else
    {
        LogWrite "User input an unknown value: $ruSure. Exiting."
        Write-Host "Unrecognized input. Exiting APT..."
        Exit
    }
}
ElseIf ($ruShure -eq "N" -or $ruSure -eq "n")
{
    LogWrite "User entered $ruSure. Exiting."
    Write-Host "User does not wish to continue. Exiting APT..."
    Exit
}
else
{
    LogWrite "User input an unknown value: $ruSure. Exiting."
    Write-Host "Unrecognized input. Exiting APT..."
    Exit
}

# Loop through each computer name in the csv and run deployment actions.
foreach ($_ in $getItems)
{
    # Set computer name to csv list item name.
    $compName = $_.Computer
    # Get list of running powershell processes.
    $prcList = Get-Process 'Powershell' -ErrorAction SilentlyContinue
    # If number of processes equals or exceedes the number set by the global variable $maxProc, pause and wait before starting another session.
    PSWait $prcList
    Write-Host ""
    Write-Host ""
    Write-Host ""
    Write-Host "Starting deployment to: $compName"
    Write-Host ""
    LogWrite "Beginning deployment to $compName"
    # Test if computer is online and available. Based on $compName session variable. If no, set $errLvl and move on to next computer.
    $isOn = TestNet $compName
    
    If ($isON -eq "Success")
    {
        $isADM = TestADM $compName
        If ($isADM -eq "Success")
        {
            $pkgFolder = CopyPackage $compName

            If ($pkgFolder -eq "Package Copy Failed" -or $pkgFolder -eq "Create RND Dest Failed" -or $pkgFolder -eq "Create Dest Failed")
            {
                ResultWrite $compName $pkgFolder
            }
            ElseIf (!($pkgFolder))
            {
                ResultWrite $compName "Script Error"
            }
            Else
            {
                $scrFile = CreateScratch $compName 

                If ($scrFile -eq "Create SCR Failed")
                {
                    ResultWrite $compName $scrFile
                }
                ElseIf (!($scrFile))
                {
                    ResultWrite $compName "Script Error"
                }
                Else
                {
                    WriteScratch $compName $pkgFolder $scrFile
                    LogWrite "Starting package execution on $compName..."
                    Write-Host "Starting package execution on $compName..."
                    Write-Host ""
                    LogWrite "Running Powershell.exe -argument ""$scratchSpce\$compName.ps1"""
                    LogWrite "See $strResults for details on the execution results"
                    Start-Process Powershell.exe -argument "$scratchSpce\$compName.ps1"
                }
            }
        }
        ElseIf ($isADM)
        {
            ResultWrite $compName $isADM
        }
        Else
        {
            ResultWrite $compName "Script Error"
        }
    }
    ElseIf ($isOn)
    {
        ResultWrite $compName $isON
    }
    Else
    {
        ResultWrite $compName "Script Error"
    }

}
# After all computers in CSV have been interrated, APT execution is complete.
LogWrite "APT execution complete."
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host "APT Execution Complete"
Write-Host ""
Write-Host ""



