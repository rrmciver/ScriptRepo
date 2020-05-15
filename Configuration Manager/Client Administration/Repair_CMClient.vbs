'SCCM Client Repair

'Description: This script will attempt to repair and reinstall the SCCM client and related services (WMI and WUAUServ).
'Can be run in multiple modes to execute more or less aggressive repair operations.

'Accepted arguments: reinstall, lite, full, quiet
'Usage Example: C:\Windows\System32\cscript.exe SCCM_Client_Repair.vbs reinstall quiet

'Modes: 
'reinstall - will perform a full uninstall and reinstall of the SCCM client. Uninstall includes removal of client certificates, registry keys, and WMI classes.
'lite - default mode. Performs 'reinstall' tasks while also executing a simple analysis and repair of the WMI Repository and Windows Update Agent.
'full - performs all 'reinstall' and 'lite' tasks, but will also force a rebuild of the WMI Repository and performs a reset of the Windows Update Agent. This mode will not run on servers.
'quiet - when specified, will not display a dialog box when script execution completes.

'References:
' https://support.microsoft.com/en-us/help/971058/how-do-i-reset-windows-update-components
' https://blogs.technet.microsoft.com/askperf/2009/04/13/wmi-rebuilding-the-wmi-repository/
' https://blogs.technet.microsoft.com/michaelgriswold/2013/01/02/manual-removal-of-the-sccm-client/

'Custom exit codes:
'3201 = repair failed or installation could not be validated. This could be due to setup still running when final validation was run. Review script and client setup logs for more information.
'3202 = Unable to locate ccmsetup.exe

On Error Resume Next

'Declare variables
Dim strMode
Dim binQuiet
Dim strComputer
Dim strPath
Dim strSMSProcess
Dim strUninstCmd
Dim strErrStatus
Dim strSMSServiceName
Dim strSMSSetupPrc
Dim strRegInstallType
Dim strInstallationType
Dim strLogFilePath
Dim strClientSharePath
Dim strSMSSiteCode
Dim strSMSInstallArgs
Dim strRegCCM
Dim strRegCCMSetup
Dim strRegSMS

'Initialize constants
Const HKEY_LOCAL_MACHINE = &H80000002

'Initialize variables
strComputer = "."
strSMSServiceName = "ccmexec"
strSMSProcess = "ccmexec.exe"
strSMSSetupPrc = "ccmsetup.exe"
strRegInstallType = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\InstallationType"

'Set log file name and path
strLogFilePath = "C:\Windows\Temp\SCCMClientRepair.log"

'Set SCCM client variables for client share UNC path, site code, and install command arguments
strClientSharePath = "\\MySiteServer\client\ccmsetup.exe"
strSMSSiteCode = "MySiteCode"
strSMSInstallArgs = "/BITSPriority:LOW SMSSITECODE=" & strSMSSiteCode

'Registry keys associated with the SCCM client. These will be deleted during uninstall process.
strRegCCM = "SOFTWARE\Microsoft\CCM"
strRegCCMSetup = "SOFTWARE\Microsoft\CCMSetup"
strRegSMS = "SOFTWARE\Microsoft\SMS"

'Created common objects needed by main script
Set objShell = WScript.CreateObject("Wscript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

'Create log file
Set objLog = objFSO.CreateTextFile(strLogFilePath, True)
WriteLog "Script execution start"

'Process arguments and set run mode
If Wscript.Arguments.Count = 0 Then
	WriteLog "No arguments passed. Defaulting to 'lite' repair mode"
	strMode = "lite"
	binQuiet = 0
Else
	If LCase(WScript.Arguments(0)) = "full" Then
		WriteLog "Setting repair mode to 'full' based on passed argument: " & wscript.arguments(0)
		strMode = "full"
	ElseIf LCase(WScript.Arguments(0)) = "lite" Then
		WriteLog "Setting repair mode to 'lite' based on passed argument: " & wscript.arguments(0)
		strMode = "lite"
	ElseIf LCase(WScript.Arguments(0)) = "reinstall" Then
		WriteLog "Setting repair mode to 'reinstall' based on passed argument: " & wscript.arguments(0)
		WriteLog "Note that only client removal and re-installation tasks will be performed. Run in 'lite' or 'full' modes for more a more aggressive repair."
		strMode = "reinstall"
	ElseIf LCase(WScript.Arguments(0)) = "quiet" Then
		WriteLog "Script will run silently. Defaulting to 'lite' repair mode."
		binQuiet = 1
	Else
		WriteLog "Setting repair mode to 'lite' due to unexpected augument: " & WScript.Arguments(0)
		strMode = "lite"
	End If
	
	If LCase(WScript.Arguments(1)) = "quiet" Then
		WriteLog "Script will run silently."
		binQuiet = 1
	Else
		If binQuiet <> 1 Then
			WriteLog "Script will not run in quiet mode. A dialog will be displayed when execution is complete."
			binQuiet = 0
		End If
	End If
End If

'Get OS Type (Client or Server) and override arguments accordingly
strInstallationType = LCase(objShell.RegRead(strRegInstallType))
If err.number <> 0 Then
	WriteLog "ERROR: Could not get OS type from registry. Defaulting OS type to: server"
	strInstallationType = "server"
Else
	WriteLog "OS type is: " & strInstallationType
End If

If strInstallationType = "server" AND strMode = "full" Then
	WriteLog "WARNING: OS type is " & strInstallationType & ". Forcing repair mode to lite"
	strMode = "lite"
End If

'Determine ccmsetup path and establish uninstall/install command strings. If ccmsetup is not found in an expected location, script will exit.
WriteLog "Determining uninstall and install command srings..."
WriteLog "Getting script execution path..."
Set objScriptFile = objFSO.GetFile(Wscript.ScriptFullName)
strScriptPath = objFSO.GetParentFolderName(objScriptFile)
WriteLog "Script execution path = " & strScriptPath
WriteLog "Checking location of ccmexec.exe..."
If objFSO.FileExists(strScriptPath & "\ccmsetup.exe") then
	WriteLog "ccmsetup.exe found in script root"
	strUninstCmd = strScriptPath & "\ccmsetup.exe /uninstall"
	strInstCmd = strScriptPath & "\ccmsetup.exe" & " " & strSMSInstallArgs
ElseIf objFSO.FileExists(strClientSharePath) Then
	WriteLog "ccmsetup.exe found on client share"
	strInstCmd = strClientSharePath & " " & strSMSInstallArgs
	strUninstCmd = strClientSharePath & " /uninstall"
Else
	WriteLog "ERROR: ccmsetup.exe was not found in any of the expected locations. Script will now exit."
	WScript.quit 3202
End If

'-------------------------------------------

'Uninstall the sccm client via setup
CCMClientUninstall

'Test if setup is still running
VerifySetupFinished

'Verify that SCCM Client service no longer exists. If is still exists, will attempt to uninstall the client again.
strErrStatus = VerifyServiceState("missing")
If strErrStatus = "False" Then
	WriteLog "WARNING: Uninstall may not have been successful. Retrying..."
	CCMClientUninstall
	VerifySetupFinished
	strErrStatus = Nothing
	strErrStatus = VerifyServiceState("missing")
	If strErrStatus = "False" Then
		WriteLog "ERROR: CCM service still exists after multiple uninstall attempts. Review ccmsetup logs for more details. Continuing with repair..."
	End If
End If
strErrStatus = Nothing

'Run cleanup to make sure sccm client is fully uninstalled
SCCMClientCleanup

'-------------------------------------------

'Repair WMI Repository and Windows Udpate Agent
If strMode = "lite" OR strMode = "full" Then
	If strInstallationType <> "server" Then
		WMIRepair
	End If
	WUAURepair
End If

'Reinstall SCCM Client
'---------------------------------------------------------
CCMClientInstall

'Verify that SCCM Client service exists
strErrStatus = VerifyServiceState ("running")

'Exit with the appropriate error code
If strErrStatus = "False" Then
	WriteLog "WARNING: SCCM Client service was not found after running installation command. Review ccmsetup logs for details."
	If binQuiet = 0 Then
		WScript.Echo "SCCM Client Repair failed with error code 3201."
	End If
	objLog.Close
	WScript.Quit 3201
ElseIf strErrStatus = "True" Then
	WriteLog "Repair completed successfully"
	WriteLog "Running SCCM Client actions..."
	RunSCCMClientActions
	WriteLog "Script execution complete"
	If binQuiet = 0 Then
		WScript.Echo "SCCM Client Repair completed successfully."
	End If
	objLog.Close
	WScript.Quit 0
Else
	WriteLog "Unexpected results returned from function: " & strErrStatus
	If binQuiet = 0 Then
		WScript.Echo "SCCM Client Repair failed with error code 3201."
	End If
	objLog.Close
	WScript.Quit 3201
End If

'--------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------


Function VerifyServiceState(strDesiredState)
	'Verifies that the ccmexec service is in the desired state and retuns 'True' or 'False'.
	'If not found in the desired state, will wait for two minutes then try again. Times out after three attempts.
	On Error Resume Next
	
	Dim strResultState
	Dim strServiceExists
	
	WriteLog "VerifyServiceState: Beginning verification of " & strSMSServiceName & " service state"
	WriteLog "VerifyServiceState: Desired state of the " & strSMSServiceName & " service is: " & strDesiredState
	If strDesiredState = "missing" Then
		strDesiredState = "False"
	ElseIf strDesiredState = "running" Then
		strDesiredState = "True"
	Else
		WriteLog "VerifyServiceState: ERROR: Unrecognized service state"
		VerifyServiceExists = "error"
		Exit Function
	End If
	
	strResultState = Empty

	strServiceExists = CheckServiceExists

	If strServiceExists = strDesiredState Then
		WriteLog "VerifyServiceState: Found service = " & strServiceExists & ". Expected = " & strDesiredState & "."
		strResultState = "True"
	Else 
		WriteLog "VerifyServiceState: WARNING: Found service = " & strServiceExists & ". Expected = " & strDesiredState & "."
		strSetupRunning = CheckSetupRunning
		If strSetupRunning = "False" Then
			WriteLog "VerifyServiceState: WARNING: Setup was not found in running processes"
			WriteLog "VerifyServiceState: WARNING: Service not found in desired state and setup process not found running."
			strResultState = "False"
		ElseIf strSetupRunning = "True" Then
			WriteLog "VerifyServiceState: Setup process found running. Waiting 120 seconds for setup to finish."
			WScript.Sleep 120000
			strSetupRunning = Empty
			strServiceExists = Empty
			strServiceExists = CheckServiceExists
			If strServiceExists = strDesiredState Then
				WriteLog "VerifyServiceState: Found service = " & strServiceExists & ". Desired = " & strDesiredState & "."
				strResultState = "True"
			Else
				WriteLog "VerifyServiceState: WARNING: Found service = " & strServiceExists & ". Desired = " & strDesiredState & "."
				strSetupRunning = CheckSetupRunning
				If strSetupRunning = "False" Then
					WriteLog "VerifyServiceState: WARNING: Setup not found in running processes"
					WriteLog "VerifyServiceState: WARNING: Service not found in desired state and setup process not found running."
					strResultState = "False"
				ElseIf strSetupRunning = "True" Then
					WriteLog "VerifyServiceState: Setup process found running. Waiting 120 seconds for setup to finish."
					WScript.Sleep 120000
					strSetupRunning = Empty
					strServiceExists = Empty
					strServiceExists = CheckServiceExists
					If strServiceExists = strDesiredState Then
						WriteLog "VerifyServiceState: Found service = " & strServiceExists & ". Desired = " & strDesiredState & "."
						strResultState = "True"
					Else
						WriteLog "VerifyServiceState: WARNING: Found service = " & strServiceExists & ". Desired = " & strDesiredState & "."
						WriteLog "VerifyServiceState: WARNING: Service not found in desired state and setup process not found running. Will not retry."
						strResultState = "False"
					End If
				End If
			End If
		Else
			WriteLog "VerifyServiceState: ERROR: Unexpected results returned from CheckSetupRunning function."
			WriteLog "VerifyServiceState: ERROR: Service not found in desired state and setup process could not be verified"
			strResultState = "False"
		End If
		strSetupRunning = Empty
		strServiceExists = Empty
	
		If strDesiredState = "True" AND strResultState = "True" Then
			WriteLog "VerifyServiceState: Verifying that service is running..."
			strSrvState = GetServiceState(strSMSServiceName)
			If LCase(strSrvState) <> "running" Then
				WriteLog "VerifyServiceState: Service was found but is not running. Setup may have failed or is still running."
				WriteLog "Returned result: " & strSrvState
				strResultState = "False"
			Else
				WriteLog "VerifyServiceState: Service found and is running."
				strResultState = "True"
			End If
		End If
	End If
	WriteLog "VerifyServiceState: Service verification results: " & strResultState
	VerifyServiceState = strResultState
End Function

Function CheckSetupRunning
	'Checks to see if setup process is still running. Returns "True" if setup process is found.
	On Error Resume Next
	
	Set objShell = WScript.CreateObject("Wscript.Shell")

	WriteLog "CheckSetupRunning: Checking to see if " & strSMSSetupPrc & " is running..."
	
	Set getProcess = objShell.Exec("C:\Windows\System32\cmd.exe /c tasklist /FI " & chr(34) & "IMAGENAME eq " & strSMSSetupPrc & chr(34))
	strProcess = getProcess.stdout.readall
	If InStr(strProcess, strSMSSetupPrc) > 1 Then
		strSetupPrcFound = "True"
	Else
		strSetupPrcFound = "False"
	End If
	
	CheckSetupRunning = strSetupPrcFound
End Function

Function CheckServiceExists
	'Checks to see if the ccmexec service exists on the computer. Returns 'True' if yes, 'False' if no.
	On Error Resume Next
	Set objShell = WScript.CreateObject("Wscript.Shell")
	strServiceExists = Empty
	WriteLog "CheckServiceExists: Checking for " & strSMSServiceName & " service"
	Set objService = objShell.Exec("C:\Windows\System32\cmd.exe /c sc query " & strSMSServiceName)
	strService = objService.stdout.readall
	If InStr(strService, strSMSServiceName) > 1 Then
		strServiceExists = "True"
	Else
		strServiceExists = "False"
	End If

	Set objService = Nothing
	CheckServiceExists = strServiceExists
End Function

Function GetServiceState(srvName)
	'Gets the current running state of the specified service. Returns Running, Stopped, Unknown, or Service Not Found
	On Error Resume Next
	Set objShell = WScript.CreateObject("Wscript.Shell")
	WriteLog "GetServiceState: Checking state of the discovered service."
	strResult = Empty
	Set objService = objShell.Exec("C:\Windows\System32\cmd.exe /c sc query " & srvName)
	strService = objService.stdout.readall
	If InStr(strService, srvName) > 1 Then
		If InStr(strResult, "RUNNING") > 1 Then
			strResult =  "Running"
		ElseIf InStr(strResult, "STOPPED") > 1 Then
			strResult = "Stopped"
		Else
			strResult = "Unknown"
		End If
	Else
		strResult = "Service Not Found"
	End If
	
	Set objService = Nothing
	GetServiceState = strResult
End Function

Function TestWMI
	'Test the current health of the WMI Repository by attempting to connect to common Namespaces and Classes. Returns 'good' if healthy, 'bad' if errors are encountered.
	'Returns 'good' if all connection attempts are successful, 'bad' if an error is encountered.
	On Error Resume Next
	WriteLog "TestWMI: Verifying WMI repository health..."
	strHealthStatus = "good"
	Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\" & strComputer & "\root\cimv2")
	If IsObject(objWMIService) Then
		WriteLog "TestWMI: Connection to root\cimv2 Namespace successful. Running query tests..."
		WriteLog "TestWMI: Running query: Select * from Win32_WMISetting"
		Set colItems = objWMIService.ExecQuery ("Select * from Win32_WMISetting")
		If colItems.Count < 1 Then
			WriteLog "TestWMI: ERROR: WMI query test failed: Win32_WMISetting"
			strHealthStatus = "bad"
		Else
			Set colItems = Nothing
			WriteLog "TestWMI: Query successfully returned results"
			WriteLog "TestWMI: Running query: Select * from Win32_OperatingSystem"
			set colItems = objWMIService.ExecQuery ("Select * from Win32_OperatingSystem")
			If colItems.Count < 1 Then
				WriteLog "TestWMI: ERROR: WMI query test failed: Win32_OperatingSystem"
				strHealthStatus = "bad"
			Else
				Set colItems = Nothing
				WriteLog "TestWMI: Query successfully returned results"
				WriteLog "TestWMI: Running query: Select * from Win32_Product"
				Set colItems = objWMIService.ExecQuery ("Select * from Win32_Product")
				If colItems.Count < 1 Then
					WriteLog "TestWMI: ERROR: WMI query test failed: Win32_Product"
					strHealthStatus = "bad"
				Else
					WriteLog "TestWMI: SUCCESS: All WMI query tests passed."
				End If
			End If
		End If
	Else
		WriteLog "TestWMI: ERROR: Could not connect to WMI Repository."
		strHealthStatus = "bad"
	End If
	Set objWMIService = Nothing
	Set colItems = Nothing
	TestWMI = strHealthStatus
End Function

Sub VerifySetupFinished
	'Verifies that the setup process is no longer running to avoid conflicts. If found running, will wait for two minutes and try again.
	'Times out and returns to caller after three attempts.
	On Error Resume Next
	
	WriteLog "VerifySetupFinished: Checking to see if setup process is still running..."
	strSetupRunning = CheckSetupRunning

	If strSetupRunning = "True" Then
		WriteLog "VerifySetupFinished: Setup process was found and is still running. Waiting 120 seconds for setup process to complete and close."
		wscript.sleep 120000
		WriteLog "VerifySetupFinished: Checking again to see if setup process is running"
		strSetupRunning = Empty
		strSetupRunning = CheckSetupRunning
		If strSetupRunning = "True" Then
			WriteLog "VerifySetupFinished: Setup is still running. Waiting another 120 seconds for setup to complete."
			wscript.sleep 120000
			WriteLog "VerifySetupFinished: Checking for setup process one more time"
			strSetupRunning = Empty
			strSetupRunning = CheckSetupRunning
			If strSetupRunning = "True" Then
				WriteLog "VerifySetupFinished: WARNING: Setup process still found. Ignoring."
			ElseIf strSetupRunning = "False" Then
				WriteLog "VerifySetupFinished: Setup process was not found. Assuming setup is complete"
			Else
				WriteLog "VerifySetupFinished: ERROR: Unexpected value (" & strSetupRunning & ") returned from CheckSetupRunning function. Assuming process was not found."
			End If
		ElseIf strSetupRunning = "False" Then
			WriteLog "VerifySetupFinished: Setup process was not found. Assuming setup is complete."
		Else
			WriteLog "VerifySetupFinished: ERROR: Unexpected value (" & strSetupRunning & ") returned from CheckSetupRunning function. Assuming process was not found and setup is complete."
		End If
	ElseIf strSetupRunning = "False" Then
		WriteLog "VerifySetupFinished: Setup process not found. Assuming setup is complete."
	Else
		WriteLog "VerifySetupFinished: ERROR: Unexpected value (" & strSetupRunning & ") returned from CheckSetupRunning function. Assuming setup process was not found and setup is complete."
	End If
	strSetupRunning = Empty
End Sub


Sub CCMClientInstall
	'Installs the SCCM Client using the established parameters
	On Error Resume Next
	
	Dim errStatus
	
	Set objShell = WScript.CreateObject("Wscript.Shell")
	
	WriteLog "CCMClientInstall: Beginning SCCM Client installation..."
	
	'Kill any running ccmsetup.exe processes
	WriteLog "CCMClientInstall: Killing running instances of " & strSMSProcess
	errStatus = objShell.Run ("taskkill /im " & strSMSProcess & " /f", 0, True)
	If errStatus <> 0 Then
		WriteLog "CCMClientInstall: WARNING: taskkill command returned exit code " & errStatus
	Else
		WriteLog "CCMClientInstall: Success"
	End If
	errStatus = Empty
	
	'Run installation command and wait five minutes for setup to complete
	WriteLog "CCMClientInstall: Executing: " & strInstCmd
	errStatus = objShell.Run (strInstCmd, 0, true)
	If errStatus <> 0 Then
		WriteLog "CCMClientInstall: WARNING: Setup command exited with error code " & errStatus
	Else
		WriteLog "CCMClientInstall: Setup exited with code " & errStatus
	End If
	Wscript.Sleep 300000
	errStatus = Empty
End Sub

Sub CCMClientUninstall
	'Uninstalls the SCCM Client via ccmsetup
	On Error Resume Next
	
	Dim errStatus
	
	Set objShell = WScript.CreateObject("Wscript.Shell")
	
	WriteLog "CCMClientUninstall: Begin SCCM Client uninstall..."
	
	'Stop SMS Agent Host service
	WriteLog "CCMClientUninstall: Stopping SMS Agent Host service"
	errStatus = objShell.Run ("net stop " & strSMSServiceName & " /y", 0, True)
	If errStatus <> 0 Then
		WriteLog "CCMClientUninstall: WARNING: net stop command returned exit code " & errStatus
	Else
		WriteLog "CCMClientUninstall: Success"
	End If
	errStatus = Empty

	'Kill any running ccmexec processes
	WriteLog "CCMClientUninstall: Killing running instances of " & strSMSProcess
	errStatus = objShell.Run ("taskkill /im " & strSMSProcess & " /f", 0, True)
	If errStatus <> 0 Then
		WriteLog "CCMClientUninstall: WARNING: taskkill command returned exit code " & errStatus
		WriteLog "CCMClientUninstall: If service was successfully stopped, this result is expected"
	Else
		WriteLog "CCMClientUninstall: Success"
	End If
	errStatus = Empty

	'Run uninstall command to remove the SCCM Client then wait three minutes for setup to complete
	WriteLog "CCMClientUninstall: Executing: " & strUninstCmd
	errStatus = objShell.Run (strUninstCmd, 0, true)
	If errStatus <> 0 Then
		WriteLog "CCMClientUninstall: WARNING: Command executed and returned exit code " & errStatus
	Else
		WriteLog "CCMClientUninstall: Command executed and returned exit code " & errStatus
	End If
	Wscript.Sleep 180000
	errStatus = Empty
End Sub

Sub SCCMClientCleanup
	On Error Resume Next
	
	Dim strCertPath
	
	'Delete files and folders related to the previous SCCM Client installation
	WriteLog "SCCMClientCleanup: Attempting clean up of previous SCCM installation..."

	If objFSO.FolderExists("C:\Windows\ccm") Then
		WriteLog "SCCMClientCleanup: Deleting C:\Windows\ccm"
		objFSO.DeleteFolder("C:\Windows\ccm"), True
		If err.number <> 0 Then
			WriteLog "SCCMClientCleanup: ERROR unable to delete folder: " & err.number
		End If
	End If

	If objFSO.FolderExists("C:\Windows\ccmcache") Then
		WriteLog "SCCMClientCleanup: Deleting C:\Windows\ccmcache"
		objFSO.DeleteFolder("C:\Windows\ccmcache"), True
		If err.number <> 0 Then
			WriteLog "SCCMClientCleanup: ERROR unable to delete folder: " & err.number
		End If
	End If

	If objFSO.FolderExists("C:\Windows\ccmsetup") Then
		WriteLog "SCCMClientCleanup: Deleting C:\Windows\ccmsetup"
		objFSO.DeleteFolder("C:\Windows\ccmsetup"), True
		If err.number <> 0 Then
			WriteLog "SCCMClientCleanup: ERROR unable to delete folder: " & err.number
		End If
	End If

	If objFSO.FileExists("C:\Windows\smscfg.ini") Then
		WriteLog "SCCMClientCleanup: Deleting C:\Windows\smscfg.ini"
		objFSO.DeleteFile("C:\Windows\smscfg.ini"), True
		If err.number <> 0 Then
			WriteLog "SCCMClientCleanup: ERROR unable to delete folder: " & err.number
		End If
	End If

	If objFSO.FileExists("C:\Windows\sms*.mif") Then
		WriteLog "SCCMClientCleanup: Deleting C:\Windows\sms*.mif"
		objFSO.DeleteFile("C:\Windows\sms*.mif"), True
		If err.number <> 0 Then
			WriteLog "SCCMClientCleanup: ERROR unable to delete folder: " & err.number
		End If
	End If

	'Delete client registry keys
	DeleteRegKey strRegCCM
	DeleteRegKey strRegCCMSetup
	DeleteRegKey strRegSMS
	
	'Delete SCCM WMI classes
	DeleteCCMClasses
	
	'Delete registry keys associate with the SMS certificates
	strCertPath = "SOFTWARE\Microsoft\SystemCertificates\SMS\Certificates"
	DeleteCertKeys strCertPath
	WriteLog "SCCMClientCleanup: SCCM Client cleanup complete"
End Sub
		
Sub WMIRepair
	On Error Resume Next
	'Evaluates the health of the WMI Repository and takes corrective action, if needed
	
	Dim strWinMgmtSvc
	Dim strWMIHealth
	Dim errStatus
	
	Set objShell = WScript.CreateObject("Wscript.Shell")
	
	strWinMgmtSvc = "winmgmt"
	
	If strInstallationType = "server" Then
		WriteLog "WMIRepair: System is of type: " & strInstallationType & ". No WMI repair tasks will be performed."
		exit sub
	End If
	
	WriteLog "WMIRepair: Begin WMI Repository repair"

	strWMIHealth = TestWMI
	
	If strMode = "full" Then
		WriteLog "WMIRepair: Running in full mode. Ignoring WMI health state and rebuilding WMI Repository..."
		WMIRebuild
	ElseIf strWMIHealth = "bad" Then
		WriteLog "WMIRepair: Attempting to salvage the WMI Repository..."
		objShell.Run "net stop " & strWinMgmtSvc & " /yes", 0, True
		objShell.Run "net start " & strWinMgmtSvc, 0, True
		errStatus = objShell.Run ("winmgmt /salvagerepository", 0, True)
		If errStatus <> 0 Then
			WriteLog "WMIRepair: WARNING: Salvage Repository attempt finished with exit code " & errStatus
			WMIRebuild
		Else
			WriteLog "WMIRepair: Salvage repository command returned a successful exit code."
		End If
	Else
		WriteLog "WMIRepair: WMI appears to be healthy. Rerun script in Full mode to ignore health state and force a repair of the WMI respository."
	End If
	errStatus = Empty
	WriteLog "WMIRepair: End WMI repair"
End Sub

Sub WMIRebuild
	'Performs a manual rebuild of the the WMI Repository
	On Error Resume Next
	
	Dim strWbemPath
	Dim strSecCentSvc
	Dim strIPHelpSvc
	Dim strWinMgmtSvc
	
	Set objShell = WScript.CreateObject("Wscript.Shell")
	
	strWbemPath = "C:\Windows\System32\wbem"
	strSecCentSvc = "wscsvc"
	strIPHelpSvc = "iphlpsvc"
	strWinMgmtSvc = "winmgmt"

	WriteLog "WMIRebuild: Attempting manual rebuild of the WMI repository"
	'Stop winmgmt service and its dependent services
	WriteLog "WMIRebuild: Stopping related WMI services..."
	WriteLog "WMIRebuild: Stopping " & strSecCentSvc
	objShell.Run "net stop " & strSecCentSvc & " /yes", 0, True
	If err.number <> 0 Then
		WriteLog "WMIRebuild: WARNING service could not be stopped: " & err.number
	End If
	WriteLog "WMIRebuild: Stopping " & strIPHelpSvc
	objShell.Run "net stop " & strIPHelpSvc & " /yes", 0, True
	If err.number <> 0 Then
		WriteLog "WMIRebuild: WARNING service could not be stopped: " & err.number
	End If
	WriteLog "WMIRebuild: Stopping SharedAccess"
	objShell.Run "net stop SharedAccess /yes", 0, True
	If err.number <> 0 Then
		WriteLog "WMIRebuild: WARNING service could not be stopped: " & err.number
	End If
	WriteLog "WMIRebuild: Stopping " & strWinMgmtSvc
	objShell.Run "net stop " & strWinMgmtSvc & " /yes", 0, True
	If err.number <> 0 Then
		WriteLog "WMIRebuild: WARNING service could not be stopped: " & err.number
	End If

	'If repository folder has been renamed before, delete the previous backup
	If (objFSO.FolderExists("C:\Windows\System32\wbem\Repository-old")) Then
		WriteLog "WMIRebuild: Found previous backup of C:\Windows\System32\wbem\Repository. Deleting..."
		objFSO.DeleteFolder("C:\Windows\System32\wbem\Repository-old")
		If err.number <> 0 Then
			WriteLog "WMIRebuild: ERROR unable to delete folder: " & err.number
		End If
	End If

	'Rename the repository folder to -old
	WriteLog "WMIRebuild: Backing up C:\Windows\System32\wbem\Repository by creating a copy named Repository-old..."
	objFSO.CopyFolder "C:\Windows\System32\wbem\Repository", "C:\Windows\System32\wbem\Repository-old"
	If err.number <> 0 Then
		WriteLog "WMIRebuild: WARNING unable to rename folder: " & err.number
	Else
		WriteLog "WMIRebuild: Backup complete, deleting C:\Windows\System32\wbem\Repository"
		objFSO.DeleteFolder("C:\Windows\System32\wbem\Repository"), True
		If err.number <> 0 Then
			WriteLog "WMIRebuild: ERROR folder could not be deleted: " & err.number
		End If
	End If
	

	'Restart the winmgmt and dependent services
	WriteLog "WMIRebuild: Restarting related WMI services..."
	WriteLog "WMIRebuild: Starting " & strWinMgmtSvc
	objShell.Run "net start " & strWinMgmtSvc, 0, True
	WriteLog "WMIRebuild: Starting " & strSecCentSvc
	objShell.Run "net start " & strSecCentSvc, 0, True
	WriteLog "WMIRebuild: Starting " & strIPHelpSvc
	objShell.Run "net start " & strIPHelpSvc, 0, True
	WriteLog "WMIRebuild: Starting SharedAccess"
	objShell.Run "net start SharedAccess", 0, True

	WriteLog "WMIRebuild: Waiting one minute for WMI to reinitialize..."
	Wscript.Sleep 60000

	'Reregister dlls, mof, and mfl files
	WriteLog "WMIRebuild: Beginning reregistration of WMI related dll, mof, and mfl files"
	Set wbemFolder = objFSO.GetFolder(strWbemPath)
	Set wbemEnFolder = objFSO.GetFolder(strWbemPath & "\" & "en-us")
	Set wbemContent = wbemFolder.Files
	Set wbemEnContent = wbemEnFolder.Files
	For Each objFile in wbemContent
		If objFSO.GetExtensionName(objFile) = "dll" then
			WriteLog "WMIRebuild: Registering " & objFile
			objShell.Run "regsvr32 /s " & objFile, 0, True
		ElseIf objFSO.GetExtensionName(objFile) = "mof" then
			WriteLog "WMIRebuild: Registering " & objFile
			objShell.Run "mofcomp " & objFile, 0, True
		End If
	Next

	For Each objFile in wbemEnContent
		If objFSO.GetExtensionName(objFile) = "mfl" then
			WriteLog "WMIRebuild: Registering " & objFile
			objShell.Run "mofcomp " & objFile, 0, True
		End If
	Next
	
	'Executing basic WMI query to force initialization of the repository
	WriteLog "WMIRebuild: Forcing WMI initialization by running a query"
	Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\" & strComputer & "\root\cimv2")
	If IsObject(objWMIService) Then
		objWMIService.ExecQuery ("Select * from Win32_OperatingSystem")
		errStatus = objShell.Run("wmic os get caption", 0, True)
		If errStatus <> 0 Then
			WriteLog "WMIRebuild: WARNING WMI query failed. Repository may not yet be fully initialized or rebuild may not have been successful."
		End If
	Else
		WriteLog "WMIRebuild: ERROR Unable to connect to create WMI object"
	End If
	Set objWMIService = Nothing
End Sub

Sub WUAURepair
	'Checks OS version and takes appropriate repair actions
	On Error Resume Next
	
	Dim errDISMRepair
	Dim getOSVersion
	Dim strOSVer
	
	WriteLog "WUAURepair: Starting Windows Update Agent repair..."
	WriteLog "WUAURepair: Attempting to get OS version..."
	Set getOSVersion = objShell.exec("C:\Windows\system32\cmd.exe /c ver")
	version = getOSVersion.stdout.readall
	Select Case True
		Case InStr(version, "n 10.") > 1 : strOSVer = "10"
		Case InStr(version, "n 6.3") > 1 : strOSVer = "8.1"
		Case InStr(version, "n 6.2") > 1 : strOSVer = "8"
		Case Else : strOSVer = "legacy"
	End Select
	
	WriteLog "WUAURepair: OS version is: " & strOSVer
	If strOSVer = "10" OR strOSVer = "8.1" OR strOSVer = "8" Then
		If strMode <> "full" then 
			WriteLog "WUAURepair: Attempting to repair the WUAU Agent with DISM..."
			errDISMRepair = objShell.Run ("DISM /online /Cleanup-Image /RestoreHealth", 0, True)
			If errDISMRepair <> 0 Then
				WriteLog "WUAURepair: DISM repair failed."
				WUAURebuild
			Else
				WriteLog "WUAURepair: DISM repair returned a successful exit code."
			End If
		Else
			WUAURebuild
		End If
	Else
		WUAURebuild
	End If
End Sub

Sub WUAURebuild
	'Manually repairs the Windows Update Agent
	'------------------------------------------------------
	On Error Resume Next
	
	Dim strWinUpdSvc
	Dim strAppIDSvc
	Dim strCryptoSvc
	Dim strBITSSvc
	
	Set objShell = WScript.CreateObject("Wscript.Shell")
	
	WriteLog "WUAURebuild: Starting rebuild of the Windows Update Agent..."
	strWinUpdSvc = "wuauserv"
	strAppIDSvc = "appidsvc"
	strCryptoSvc = "cryptsvc"
	strBITSSvc = "BITS"

	'Stop Windows Update service
	WriteLog "WUAURebuild: Stopping Windows Update and related services..."
	objShell.Run "net stop " & strWinUpdSvc & " /yes", 0, True
	If err.number <> 0 Then
		WriteLog "WUAURebuild: WARNING Unable to stop service " & strWinUpdSvc & ": " & err.number
	End If
	'Stop AppID service
	objShell.Run "net stop " & strAppIDSvc & " /yes", 0, True
	If err.number <> 0 Then
		WriteLog "WUAURebuild: WARNING Unable to stop service " & strAppIDSvc & ": " & err.number
	End If
	'Stop Cryptographic service
	objShell.Run "net stop " & strCryptoSvc & " /yes", 0, True
	If err.number <> 0 Then
		WriteLog "WUAURebuild: WARNING Unable to stop service " & strCryptoSvc & ": " & err.number
	End If
	'Stop BITS Service
	objShell.Run "net stop " & strBITSSvc & " /yes", 0, True
	If err.number <> 0 Then
		WriteLog "WUAURebuild: WARNING Unable to stop service " & strBITSSvc & ": " & err.number
	End If
	
	'If Windows Update has been repaired previously, delete the previous backup
	If (objFSO.FolderExists("C:\Windows\SoftwareDistribution-old")) Then
		WriteLog "WUAURebuild: Previous backup of C:\Windows\SoftwareDistribution found. Deleting..."
		objFSO.DeleteFolder("C:\Windows\SoftwareDistribution-old")
		If err.number <> 0 Then
			WriteLog "WUAURebuild: WARNING Folder could not be deleted: " & err.number
		End If
	End If
	
	'Rename the SoftwareDistribution folder to -old
	WriteLog "Creating backup of C:\Windows\SoftwareDistribution by creating a copy named SoftwareDistribution-old"
	objFSO.CopyFolder "C:\Windows\SoftwareDistribution", "C:\Windows\SoftwareDistribution-old"
	If err.number <> 0 Then
		WriteLog "WUAURebuild: ERROR Folder could not be renamed: " & err.number
	End If
	WriteLog "Backup complete. Deleting C:\Windows\SoftwareDistribution"
	objFSO.DeleteFolder ("C:\Windows\SoftwareDistribution"), True
	If err.number <> 0 Then
		WriteLog "WUAURebuild: WARNING Folder could not be deleted: " & err.number
	End If
	
	If strMode = "full" Then
		'Delete BITS dat files associated with Windows Update
		WriteLog "WUAURebuild: Deleting BITS dat files associated with Windows Update..."
		Set netFolder = objFSO.GetFolder("C:\ProgramData\Microsoft\Network\Downloader")
		Set netContent = netFolder.Files
		For Each objFile in netContent
			If objFSO.GetExtensionName(objFile) = "dat" Then
				If instr(objFile.Name, "qmgr") = 1 Then
					WriteLog "WUAURebuild: Deleting " & objFile
					objFSO.DeleteFile(objFile), True
					If err.number <> 0 Then
						WriteLog "WUAURebuild: WARNING File could not be deleted: " & err.number
					End If
				End If
			End If
		Next


		'If catroot2 has been repaired previously, delete the previous backup
		If (objFSO.FolderExists("C:\Windows\System32\catroot2-old")) Then
			WriteLog "WUAURebuild: Previous backup of C:\Windows\System32\catroot2 found. Deleting..."
			objFSO.DeleteFolder("C:\Windows\System32\catroot2-old")
			If err.number <> 0 Then
				WriteLog "WUAURebuild: WARNING Folder could not be deleted: " & err.number
			End If
		End If
	
		'Rename the catroo2 folder to -old
		WriteLog "WUAURebuild: Creating backup of C:\Windows\System32\catroot2 by creating a copy named C:\Windows\System32\catroot2-old"
		objFSO.CopyFolder "C:\Windows\System32\catroot2", "C:\Windows\System32\catroot2-old"
		If err.number <> 0 Then
			WriteLog "WUAURebuild: ERROR Folder could not be renamed: " & err.number
		End If
		WriteLog "Backup complete. Deleting C:\Windows\System32\catroot2"
		objFSO.DeleteFolder ("C:\Windows\System32\catroot2"), True
		If err.number <> 0 Then
			WriteLog "WUAURebuild: WARNING Folder could not be deleted: " & err.number
		End If
	End If


	'Reregister BITS, Windows Update dlls
	WriteLog "WUAURebuild: Reregistering BITS and Windows Update dlls.."
	If strMode = "full" Then
		objShell.Run "sc.exe sdset bits D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)", 0, True
		objShell.Run "sc.exe sdset wuauserv D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)", 0, True
	End If
	objShell.Run "RegSvr32 -s C:\Windows\System32\atl.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\urlmon.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\mshtml.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\shdocvw.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\browseui.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\jscript.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\vbscript.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\scrrun.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\msxml.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\msxml3.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\msxml6.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\actxprxy.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\softpub.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\wintrust.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\dssenh.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\rsaenh.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\gpkcsp.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\sccbase.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\slbcsp.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\cryptdlg.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\oleaut32.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\ole32.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\shell32.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\initpki.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\wuapi.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\wuaueng.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\wuaueng1.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\wucltui.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\wups.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\wups2.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\wuweb.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\qmgr.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\qmgrprxy.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\wucltux.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\muweb.dll", 0, True
	objShell.Run "RegSvr32 -s C:\Windows\System32\wuwebv.dll", 0, True

	If strMode = "full" Then
		'Reset winsock and winhttp proxy
		WriteLog "WUAURebuild: Resetting winsock and proxy settings..."
		objShell.Run "netsh winsock reset", 0, True
		objShell.Run "netsh winhttp reset proxy", 0, True
	End If
	
	WriteLog "WUAURebuild: Startting Windows Update and related services..."
	'Star BITS Service
	objShell.Run "net start " & strBITSSvc, 0, True
	'Start Cryptographic service
	objShell.Run "net start " & strCryptoSvc, 0, True
	'Start AppID service
	objShell.Run "net start " & strAppIDSvc, 0, True
	'Start Windows Update service
	objShell.Run "net start " & strWinUpdSvc, 0, True
	
	WriteLog "WUAURebuild: Windows Update repair completed"
	'------------------------------------------------------
End Sub

Sub RunSCCMClientActions
	'Executes Machine Policy Retrieval and Evaluation Cycles to initiate client communication
	On Error Resume Next
	
	Dim strSMSAction1
	Dim strSMSAction2
	
	Set objShell = WScript.CreateObject("Wscript.Shell")
	
	strSMSAction1 = "WMIC /namespace:\\root\ccm path sms_client CALL TriggerSchedule '{00000000-0000-0000-0000-000000000021}' /NOINTERACTIVE"
	strSMSAction2 = "WMIC /namespace:\\root\ccm path sms_client CALL TriggerSchedule '{00000000-0000-0000-0000-000000000022}' /NOINTERACTIVE"
	WriteLog "RunSCCMClientActions: Initiating SCCM Client action: Machine Policy Retrieval Cycle"
	WriteLog "RunSCCMClientActions: Executing: " & strSMSAction1
	objShell.Run strSMSAction1, 0, True
	WriteLog "RunSCCMClientActions: Initiating SCCM Client action: Machine Policy Evaluation Cycle"
	WriteLog "RunSCCMClientActions: Executing: " & strSMSAction2
	objShell.Run strSMSAction2, 0, True
End Sub


Sub DeleteCertKeys(strCertPath)
	On Error Resume Next
	'Deletes SCCM Client certificates
	Set objRegistry = GetObject("winmgmts:\\" & strComputer & "\root\default:StdRegProv")
	WriteLog"DeleteCertKeys: Searching for SMS certificate registry keys under HKLM\" & strCertPath
	objRegistry.EnumKey HKEY_LOCAL_MACHINE, strCertPath, arrSubkey
	If IsArray(arrSubKey) Then
		For Each strSubkey In arrSubkey
			WriteLog "DeleteCertKeys: Found " & strSubKey
			objRegistry.DeleteKey HKEY_LOCAL_MACHINE, strCertPath & "\" & strSubKey
			WriteLog "DeleteCertKeys: HKLM\" & strCertPath & "\" & strSubKey & " deleted"
		Next
	End If
	Set objRegistry = Nothing
End Sub

Sub DeleteRegKey(strKeyPath)
	On Error Resume Next
	'Deletes the passed registry key
	Set objRegistry = GetObject("winmgmts:\\" & strComputer & "\root\default:StdRegProv")
	WriteLog "DeleteRegKey: Testing for registry key HKLM\" & strKeyPath
	objRegistry.RegRead(strKeyPath)
	If err.number = 0 Then
		WriteLog "DeleteRegKey: Key found. Deleting... "
		objRegistry.DeleteKey HKEY_LOCAL_MACHINE, strKeyPath
		If err.number = 0 Then
			WriteLog "DeleteRegKey: HKLM\" & strKeyPath & " has been deleted."
		Else
			WriteLog "DeleteRegKey: WARNING failed to delete key " & strKeyPath & " . Error number: " & err.number
		End If
	Else
		WriteLog "DeleteRegKey: Key not found or could not be read: " & err.number
	End If
	Set objRegistry = Nothing
End Sub

Sub DeleteCCMClasses
	'Deletes WMI classes assocaited with the SCCM client
	On Error Resume Next
	WriteLog "DeleteCCMClasses: Attempting to delete lingering SCCM Client WMI classes"
	WriteLog "DeleteCCMClasses: Attempting to connect to WMI namespace: root"
	Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\" & strComputer & "\root")
	If IsObject(objWMIService) Then
		WriteLog "DeleteCCMClasses: Successfully connected to namespace. Attempting to connect to class 'ccm'"
		Set objItem = objWMIService.Get("__Namespace.Name='ccm'")
		If err.number <> 0 Then
			WriteLog "DeleteCCMClasses: WARNING unable to find class under the current namespace: " & err.number
		Else
			WriteLog "DeleteCCMClasses: Class found. Deleting..."
			objItem.Delete_
			If err.number <> 0 then
				WriteLog "DeleteCCMClasses: ERROR class could not be deleted: " & err.number
			Else
				WriteLog "DeleteCCMClasses: CCM class deleted successfully"
			End If
		End If
		Set objItem = Nothing
		Set objWMIService = Nothing
	Else
		WriteLog "DeleteCCMClasses: ERROR connecting to namespace: " & err.number
	End If
	
	WriteLog "DeleteCCMClasses: Attempting to connect to WMI namespace: root\cimv2"
	Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\" & strComputer & "\root\cimv2")
	If IsObject(objWMIService) Then
		WriteLog "DeleteCCMClasses: Successfully connected to namespace. Attempting to connect to class 'sms'"
		Set objItem = objWMIService.Get("__Namespace.Name='sms'")
		If err.number <> 0 Then
			WriteLog "DeleteCCMClasses: WARNING unable to find class under the current namespace: " & err.number
		Else
			WriteLog "DeleteCCMClasses: Class found. Deleting..."
			objItem.Delete_
			If err.number <> 0 then
				WriteLog "DeleteCCMClasses: ERROR class could not be deleted: " & err.number
			Else
				WriteLog "DeleteCCMClasses: CCM class deleted successfully"
			End If
		End If
		Set objItem = Nothing
	Else
		WriteLog "DeleteCCMClasses: ERROR connecting to namespace: " & err.number
	End If
	Set objWMIService = Nothing
End Sub

Sub WriteLog(LogText)
	'Writes to log file
	objLog.WriteLine NOW & " - " & LogText
End Sub
