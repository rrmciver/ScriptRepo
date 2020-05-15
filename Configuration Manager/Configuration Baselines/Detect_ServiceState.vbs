'Checks to see if a service is in the desired state

strServiceName = "wuauserv"

Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
Set colListOfServices = objWMIService.ExecQuery ("Select * from Win32_Service Where Name ='" & strServiceName & "'")
For Each objService in colListOfServices
	status = objService.State
Next

If status = "Stopped" Then
	WScript.Echo status

ElseIf status = "Running" Then
	Wscript.Echo status
End If
