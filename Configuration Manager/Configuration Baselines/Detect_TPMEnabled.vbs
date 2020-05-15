'Checks if the TPM is enabled and visible to the OS

strComputer = "."
Set objWMIService = GetObject("winmgmts:" _
    & "{impersonationLevel=impersonate}!\\" & strComputer & "\root\cimv2\security\MicrosoftTPM")

Set colItems = objWMIService.ExecQuery("Select * from Win32_TPM")

If colItems.count < 1 Then
	WScript.Echo "TPM is not Enabled"
Else
	WScript.Echo "TPM is Enabled"
End If