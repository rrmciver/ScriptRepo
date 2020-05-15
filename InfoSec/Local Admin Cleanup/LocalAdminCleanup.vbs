'***************************LocalAdminCleanup.vbs*************************************

'Description: This script will search for an remove unapproved users and groups from the local Administrators group. If desired, will also verify that the local Administrator account is enabled before taking action.
'Approved users and groups are provided via a text file that includes the names and scope of the approved objects. Scope can include a specific computer name or OU.
'The script will first look for the text file on a unc file share path, then in the script's execution directory.
'Unapproved local user accounts are also disabled after being removed from the Administrators group. Domain objects are simply removed from the group.
'If the local Administrator account is disabled, a temporary password will be created and set based on the time stamp of the execution. Recommend using another tool, such as LAPS, to manage local Admin account passwords.
'A log file will be written to the UNC share if accessible, or the local Windows\Temp directory.

'Exit code 3201 = unable to open or create log file

'Updated: 2/1/2018
'***************************************************************************

On Error Resume Next
strComputer = "."

strApprovedListFile = "\\UNC\Config\approved.txt"
binAthenaOnly = 0

'Get current script directory and set local list file path
strScriptPath = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
strLocalListFile = strScriptPath & "\approved.txt"

'Get the computer name for log file and account logic
Set wshNetwork = CreateObject("WScript.Network")
strComputerName = wshNetwork.ComputerName

'Set log file path and file name
strLogFileName = strComputerName & ".log"
strLogFolderPath = "\\UNC\Logs"
'Test if UNC log path exists. If not, switch to a local log path
Set objFSO = CreateObject("Scripting.FileSystemObject")
If objFSO.FolderExists(strLogFolderPath) Then
	strLogFilePath = strLogFolderPath & "\" & strLogFileName
Else
	strLogFilePath = "C:\Windows\Temp\LocalAdminCleanup_" & strLogFileName
End If

'If an existing log file exists for this computer, open it for appending. Else, create a new one.
If objFSO.FileExists(strLogFilePath) Then
	Set objLogFile = objFSO.OpenTextFile(strLogFilePath, 8)
	If err.number <> 0 Then
		'WScript.Echo "ERROR: Unable to open log file"
		WScript.Quit 3201
	End If
Else
	Set objLogFile = objFSO.CreateTextFile(strLogFilePath, True)
	If err.number <> 0 Then
		'WScript.Echo "ERROR: Unable to create log file"
		WScript.Quit 3201
	End If
End If

WriteLog "Start LocalAdminCleanup script execution"

'Test that account list is accessible. If not found, retire Athena then exit
If objFSO.FileExists(strApprovedListFile) Then
	Set objApprovedList = objFSO.OpenTextFile(strApprovedListFile)
ElseIf objFSO.FileExists(strLocalListFile) Then
	Set objApprovedList = objFSO.OpenTextFile(strLocalListFile)
Else
	WriteLog "ERROR: Account list file not found or inaccessible."
End If

'Test connecting to ADSI to get local users and groups
Set objLocalComputer = GetObject("WinNT://" & strcomputer)
If err.number <> 0 Then
	WriteLog "ERROR " & err.number & ": Unable to connect to ADSI to retrieve local accounts. Exiting script."
	WScript.Quit 1603
End If
Set objLocalComputer = Nothing

'Ensure local Administrator account is enabled. Comment out this call if desired.
EnableLocalAdmin

'Begin analysis of approved account list file
	'Get this computer's OU
	strOUName = GetComputerOU

	'Read each line from the text file and add them to an array. Count is used for debugging to determine the number of lines read.
	intCount = 0
	ReDim approvedListFileContents(-1)
	Do while NOT objApprovedList.AtEndOfStream
		intCount = intCount + 1
		ReDim Preserve approvedListFileContents(uBound(approvedListFileContents) + 1)
		approvedListFileContents(UBound(approvedListFileContents)) = objApprovedList.ReadLine
	Loop
	
	'Validate data from file. If first line is blank, quit.
	If IsArray(approvedListFileContents) Then
		If Trim(approvedListFileContents(0)) = "" Then
			WriteLog "ERROR: First line in text file is empty. Exiting script."
			WScript.Quit 1603
		End If
	ElseIf TypeName(approvedListFileContents) = "String" Then
		If Trim(approvedListFileContents) = "" Then
			WriteLog "ERROR: First line in text file is empty. Exiting script."
			WScript.Quit 1603
		End If
	Else
		WriteLog "ERROR: Could not validate text file date. Exiting script."
		WScript.Quit 1603
	End If
	objApprovedList.close
	
	'Parse data read from file and generate approved list of accounts for this computer
	intCount = 0
	ReDim arrApprovedList(-1)
	For Each strLine in approvedListFileContents
		intCount = intCount + 1
		arrSplitLine = Split(strLine, ",")
		arrSplitLineSize = UBound(arrSplitLine) + 1
		'If multiple criteria found in line, parse the line to determine the scope
		If arrSplitLineSize > 1 Then
			strApprovedAccount = arrSplitLine(0)
			If InStr(arrSplitLine(1), "#") = 0 Then
				strApprovedScope = Trim(arrSplitLine(1))
			Else
				strApprovedScope = "all"
			End If
			'If scope matchines this computer's computers name or OU, add it to the approved accounts list
			If LCase(strApprovedScope) = LCase(strComputerName) OR LCase(strApprovedScope) = LCase(strOUName) OR strApprovedScope = "all" Then
				ReDim Preserve arrApprovedList(uBound(arrApprovedList) + 1)
				arrApprovedList(UBound(arrApprovedList)) = strApprovedAccount
			'If scope contains a wildcard character, analyze the characters before the wildcard to determine applicability of this computer
			ElseIf InStr(strApprovedScope, "*") > 0 Then
				intCodeLength = Len(strApprovedScope) -1
				strApprovedOrgCode = Left(strApprovedScope, intCodeLength)
				strCurrentOrgCode = Left(strComputerName, intCodeLength)
				If LCase(strCurrentOrgCode) = LCase(strApprovedOrgCode) Then
					ReDim Preserve arrApprovedList(uBound(arrApprovedList) + 1)
					arrApprovedList(UBound(arrApprovedList)) = strApprovedAccount
				Else
					'WriteLog "Prefixes do not match. Account is not approved on this computer."
				End If
			'If no matching criteria and unable to get current OU name, assume account is approved
			ElseIf strOUName = "error" Then
				ReDim Preserve arrApprovedList(uBound(arrApprovedList) + 1)
				arrApprovedList(UBound(arrApprovedList)) = strApprovedAccount
			Else
				'WriteLog "Account is not authorized on this computer. It will not be added to the approved list."
			End If
		'If single item in line, assume it is a username and scope is all computers
		ElseIf arrSplitLineSize = 1 Then
			ReDim Preserve arrApprovedList(uBound(arrApprovedList) + 1)
			arrApprovedList(UBound(arrApprovedList)) = strLine
		Else
			If intCount = 1 Then 
				WriteLog "ERROR: Line " & intCount & " - Could not determine size of split line array. First line is blank or data could be corrupted. Exiting script to avoid conflicts."
				WScript.Quit 1603
			Else
				'WriteLog "WARNING: Line " & intCount & " - Could not determine size of split line array. Line may be blank.
			End If
		End If
	Next
	
	'Pass approved accounts list to subrutine for action
	CleanUpLocalAdministrators arrApprovedList


'Finished main
WriteLog "Script execution complete"
objLogFile.close

'Removes accounts from the local administrators group not found in the approved accounts list
Sub CleanUpLocalAdministrators(arrAccounts)
	On Error Resume Next
	'WriteLog "Cleaning up local Administrators group..."
	'Get all current members of the local Administrators group
	Set objLocalGroup = GetObject("WinNT://" & strComputer & "/Administrators")
	If err.number <> 0 Then
		WriteLog "ERROR " & err.number & ": Unable to retrieve list of local Administrators from ADSI"
		Exit Sub
	End If
	
	removedAccountsCount = 0
	
	'Iterate through each group member and compare it against provided accounts list. If no match found, remove it from the group
	For Each objLocalMember In objLocalGroup.Members
		binInApprovedList = 0
		arrDomainName = Split(objLocalMember.ADSPath,"/")
		strDomainName = arrDomainName(2)
		strLocalMember = strDomainName & "\" & objLocalMember.Name
		If IsArray(arrAccounts) = "True" Then
			For Each userName In arrAccounts
				'Check if approved account is a domain or local user
				strUserName = CheckDomainOrLocal(userName)
				'Compare the current group member user name to the approved user name. If they are equal, flag the the account to be ignored.
				If LCase(strLocalMember) = LCase(strUserName) Then
					binInApprovedList = 1
				End If
			Next
		ElseIf TypeName(arrAccounts) = "String" Then
			'Check if approved account is a domain or local user
			strUserName = CheckDomainOrLocal(arrAccounts)
			'Compare the current group member user name to the approved user name. If they are equal, flag the the account to be ignored.
			If LCase(strLocalMember) = LCase(strUserName) Then
					binInApprovedList = 1
			End If
		Else
			WriteLog "Error: Unable to determine type of variable passed to the sub. No further action will be taken."
			Exit Sub
		End If
		
		'If no match was found in the approved accounts list, remove the user account form the local Administrators group
		If binInApprovedList = 0 AND objLocalMember.Name <> "Administrator" Then
			WriteLog "Removing from local Administrators group: " & objLocalMember.Class & " " & strDomainName & "\" & objLocalMember.Name
			objLocalGroup.Remove(objLocalMember.AdsPath)
			'If user account is local, also disable the account
			If strDomainName = strComputerName Then
				DisableLocalUser objLocalMember.Name
			End If
			removedAccountsCount = removedAccountsCount + 1
		End If
	Next
	
	'If changes were made, run SCCM client actions to update inventory data
	If removedAccountsCount > 0 Then
		RunSCCMClientActions
	End If

	Set objLocalGroup = Nothing
	'WriteLog "Finished clean up of local Administrators group"
End Sub

'Remove an individual account from the local administrators group
Sub RemoveFromLocalAdministrators(strAccount)
	On Error Resume Next
	Set objLocalGroup = GetObject("WinNT://" & strComputer & "/Administrators")
	If err.number <> 0 Then
		WriteLog "ERROR " & err.number & ": Unable to retrieve list of local Administrators from ADSI"
		Exit Sub
	End If
	
	'WriteLog "Checking each group member against provided accounts..."
	For Each objLocalMember In objLocalGroup.Members
		If LCase(objLocalMember.Name) = LCase(strAccount) Then
			arrDomainName = Split(objLocalMember.ADSPath,"/")
			strDomainName = arrDomainName(2)
			'WriteLog "Found matching " & objLocalMember.Class & " in local Administrators group: " & strDomainName & "\" & objLocalMember.Name
			WriteLog "Removing from local Administrators group: " & objLocalMember.Class & " " & strDomainName & "\" & objLocalMember.Name
			objLocalGroup.Remove(objLocalMember.AdsPath)
		End If
	Next
	Set objLocalGroup = Nothing
	'WriteLog "Finished removal from local Administrators group"
End Sub

'Disables a local user account
Sub DisableLocalUser(strAccount)
	On Error Resume Next
	Set objLocalUser = GetObject("WinNT://" & strComputer & "/" & strAccount & ",user")
	If err.number = 0 Then
		If objLocalUser.AccountDisabled = False Then
			WriteLog "Disabling local user: " & strComputerName & "\" & objLocalUser.Name
			objLocalUser.AccountDisabled = True
			objLocalUser.SetInfo
		ElseIf objLocalUser.AccountDisabled = True Then
			'WriteLog "User is already disabled: " & strComputerName & "\" & objLocalUser.Name
		Else
			WriteLog "WARNING: Unable to determine account status to disable: " & strComputerName & "\" & objLocalUser.Name
		End If
	Else
		WriteLog "ERROR: Unable to find user to disable: " & strComputerName & "\" & objLocalUser.Name
	End If
End Sub

'Checks to see if the local Administrator account is disabled and, if so, enables it and sets a temporary password
Sub EnableLocalAdmin
	On Error Resume Next
	Set objAdmin = GetObject("WinNT://" & strComputer & "/Administrator" & ",user")
	If err.number = 0 then
		If objAdmin.AccountDisabled = True Then
			WriteLog "Enabling local account: " & strComputerName & "/Administrator"
			objAdmin.AccountDisabled = False
			strTempPassword = CreateTempPassword
			WriteLog "Temporary password set: " & strTempPassword
			objAdmin.SetPassword(strTempPassword)
			objAdmin.SetInfo
		ElseIf objAdmin.AccountDisabled = False Then
			'WriteLog "Local Administrator account is Enabled."
		End If
	Else
		'WriteLog "Warning: Local Administrator account not found."
	End If
	Set objAdmin = Nothing
End Sub

'Executes SCCM client actions
Sub RunSCCMClientActions
	On Error Resume Next
	strSMSAction1 = "WMIC /namespace:\\root\ccm path sms_client CALL TriggerSchedule '{00000000-0000-0000-0000-000000000021}' /NOINTERACTIVE"
	strSMSAction2 = "WMIC /namespace:\\root\ccm path sms_client CALL TriggerSchedule '{00000000-0000-0000-0000-000000000022}' /NOINTERACTIVE"
	strSMSAction3 = "WMIC /namespace:\\root\ccm path sms_client CALL TriggerSchedule '{00000000-0000-0000-0000-000000000001}' /NOINTERACTIVE"
	Set objShell = WScript.CreateObject("Wscript.Shell")
	'WriteLog "Initiating SCCM Client action: Machine Policy Retrieval Cycle"
	objShell.Run strSMSAction1, 0, True
	'WriteLog "Initiating SCCM Client action: Machine Policy Evaluation Cycle"
	objShell.Run strSMSAction2, 0, True
	'WriteLog "Initiating SCCM Client action: Hardware Inventory Cycle"
	objShell.Run strSMSAction3, 0, True
End Sub

'Writes to the log file
Sub WriteLog(LogText)
	On Error Resume Next
	objLogFile.WriteLine NOW & " : " & LogText
End Sub

'Checks to see if the user account is a local or domain account
Function CheckDomainOrLocal(strAccount)
	strListUser = strAccount
	arrUserNameDomain = Split(strListUser, "\")
	intUserNameDomainSize = UBound(arrUserNameDomain) + 1
	If intUserNameDomainSize = 1 Then
		strListUser = strComputerName & "\" & strListUser
	End If
	CheckDomainOrLocal = strListUser
End Function

'Creates a temporary password based on timestamp
Function CreateTempPassword()
	dateNow = FormatDateTime(Now,1)
	timeNow = FormatDateTime(Now,vbShortTime)
	arrDate = Split(dateNow, ",")
	arrTime = Split(timeNow, ":")
	strDate = Join(arrDate)
	strTime = Join(arrTime)
	strPassword = Replace(strDate, " ", "") & Replace(strTime, " ", "")
	CreateTempPassword = strPassword
End Function

'Gets the current OU of the computer. Lowest level OU name only.
Function GetComputerOU()
	On Error Resume Next
	strOUName = Empty
	Set objADSysInfo = CreateObject("ADSystemInfo")
	If err.number <> 0 Then
		WriteLog "Error: Unable to create ADSystemInfo object"
	Else
		Set objComputer = GetObject("LDAP://" & objADSysInfo.ComputerName)
		If err.number <> 0 Then
			WriteLog "Error: Unable to get LDAP information for computer"
			strOUName = "error"
		Else
			strDistName = objComputer.DistinguishedName
			arrOUs = Split(strDistName, ",")
			arrLLOU = Split(arrOUs(1), "=")
			strOUName = arrLLOU(1)
		End If
	End If
	'WriteLog "Lowest level OU: " & strOUName
	GetComputerOU = strOUName
End Function






