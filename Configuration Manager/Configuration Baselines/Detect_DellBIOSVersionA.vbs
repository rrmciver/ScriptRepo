'Detection_DellBIOSVersion
'Use this script to detect the BIOS version if the format is A## (ex: A03)
'Example: To detect if the install BIOS version is at least A16, set:
' intBIOSVersionNumber = 16

strComputer = "."

intBIOSVersionNumber = 16

Set objWMIService = GetObject("winmgmts:" _
    & "{impersonationLevel=impersonate}!\\" & strComputer & "\root\cimv2")

Set colItems = objWMIService.ExecQuery("Select * from Win32_BIOS")

If colItems.count < 1 Then
	'WScript.Echo "Query failed"
Else
	For Each item in colItems
		strBIOSVER = item.SMBIOSBIOSVersion
	Next
	arrBIOSVER = Split(strBIOSVER, "A")
	intBIOSVER = CInt(arrBIOSVER(1))
	If (intBIOSVER < intBIOSVersionNumber) Then
		'WScript.Echo "BIOS out of date: " & strBIOSVER
	Else
		WScript.Echo "BIOS updated"
	End If
End If