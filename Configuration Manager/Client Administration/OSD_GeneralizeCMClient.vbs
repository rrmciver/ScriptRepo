'SCCMPrep.vbs

'This script can be used to generalize the SCCM client on a reference computer before running sysprep and image capture.
'This script should be rerun if the computer or SMS Agent Host service is restarted after initial execution.

Const HKEY_LOCAL_MACHINE = &H80000002

strComputer = "."
strCertPath = "SOFTWARE\Microsoft\SystemCertificates\SMS\Certificates"

Set objShell = WScript.CreateObject("Wscript.Shell")

objShell.Run "Net Stop CcmExec", 0, True

DeleteCertKeys HKEY_LOCAL_MACHINE, strCertPath

Set objFSO = CreateObject("Scripting.FileSystemObject")

If objFSO.FileExists("C:\Windows\smscfg.ini") Then
	objFSO.DeleteFile("C:\Windows\smscfg.ini"), True
End If

Sub DeleteCertKeys(HKEY_LOCAL_MACHINE, strCertPath)
	'Deletes SCCM Client certificates
	On Error Resume Next
	Set objRegistry = GetObject("winmgmts:\\" & strComputer & "\root\default:StdRegProv")
	objRegistry.EnumKey HKEY_LOCAL_MACHINE, strCertPath, arrSubkey
	If IsArray(arrSubKey) Then
		For Each strSubkey In arrSubkey
			objRegistry.DeleteKey HKEY_LOCAL_MACHINE, strCertPath & "\" & strSubKey
		Next
	End If
End Sub