'Detection_DellBIOSVersion
'Use this script to detect the BIOS version if the format is a decimal separated number value
'Example: To detect if the install BIOS version is at least 1.2.3, set:
' intBIOSVersionMajor = 1
' intBIOSVersionMinor = 2
' intBIOSVersionRevision = 3

strComputer = "."
intUpdated = 0

intBIOSVersionMajor = 1
intBIOSVersionMinor = 2
intBIOSVersionRevision = 3

Set objWMIService = GetObject("winmgmts:" _
    & "{impersonationLevel=impersonate}!\\" & strComputer & "\root\cimv2")

Set colItems = objWMIService.ExecQuery("Select * from Win32_BIOS")

If colItems.count < 1 Then
	'WScript.Echo "Query failed"
Else
	For Each item in colItems
		strBIOSVER = item.SMBIOSBIOSVersion
	Next
	arrBIOSVER = Split(strBIOSVER, ".")
	intVerMajor = CInt(arrBIOSVER(0))
	intVerMinor = CInt(arrBIOSVER(1))
	intVerRev = CInt(arrBIOSVER(2))
	If (intVerMajor > intBIOSVersionMajor) Then
		intUpdated = 1
	ElseIf (intVerMajor = intBIOSVersionMajor) Then
		If (intVerMinor > intBIOSVersionMinor) then
			intUpdated = 1
		ElseIf (intVerMinor = intBIOSVersionMinor) Then
			If (intVerRev >= intBIOSVersionRevision) Then
				intUpdated = 1
			Else
				'Not updated
			End If
		Else
			'Not updated
		End If
	Else
		'Not updated
	End If

	If intUpdated = 1 Then
		WScript.Echo "BIOS is up to date"
	Else
		'WScript.Echo "BIOS is out of date"
	End If
End If