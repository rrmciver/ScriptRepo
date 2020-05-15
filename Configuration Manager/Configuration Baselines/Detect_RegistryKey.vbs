'Detects the existence of a registry key

Const HKLM = &H80000002
strKey = "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{90160000-0011-0000-0000-0000000FF1CE}"
test = KeyExists(HKLM,strKey) 
If test = "True" Then
wscript.echo "Office 2016 is installed"
End If


Function KeyExists(Key, KeyPath)
  Dim oReg: Set oReg = GetObject("winmgmts:!root/default:StdRegProv")
  If oReg.EnumKey(Key, KeyPath, arrSubKeys) = 0 Then
    KeyExists = True
  Else
    KeyExists = False
  End If
End Function