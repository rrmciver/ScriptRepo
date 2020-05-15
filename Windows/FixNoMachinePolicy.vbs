'Fix No Machine Policy
'This script resolves the issue of computers not processing and applying machine policy.

On Error Resume Next
strLogFilePath = "C:\Windows\Temp\FixNoMachinePolicy.log"
strRegKey = "HKLM\Software\Microsoft\Windows NT\CurrentVersion\WinLogon\GPExtensions\{827D319E-6EAC-11D2-A4EA-00C04F79F83A}\NoMachinePolicy"
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objLogFile = objFSO.CreateTextFile(strLogFilePath, True)
WriteLog "Start script"
Set wshShell = WScript.CreateObject("WScript.Shell")
WriteLog "Attempting to read: " & strRegKey
strValue = wshShell.RegRead(strRegKey)
If err.number <> 0 Then
	'value does not exist
	WriteLog "Reg key not found."
	errExitCode = 0
Else
	WriteLog "Reg key found. Deleting..."
	wshShell.RegDelete strRegKey
	If err.number <> 0 Then
		WriteLog "ERROR: Delete operation returned error number " & err.number
		errExitCode = err.number
	Else
		WriteLog "Delete operation returned successful"
		errExitCode = 0
	End If
End If
WriteLog "Exiting script with error code " & errExitCode
obLogFile.close
wscript.quit errExitCode

Sub WriteLog(LogText)
	'Writes to the log file
	objLogFile.WriteLine NOW & " - " & LogText
End Sub