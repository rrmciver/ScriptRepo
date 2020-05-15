'Checks to see if a registry value is set as desired. 

Const HKCU = &H80000001
strKeyPath = "Software\VMware, Inc.\VMware VDM\Client"
strValueName = "DesktopLayout"

Set objRegistry = GetObject("winmgmts:!root/default:StdRegProv")

 objRegistry.GetStringValue HKCU,strKeyPath,strValueName,strValue
 If IsNull(strValue) Then
    wscript.echo "Value not found"
 Elseif strValue="FullScreen" then
    wscript.echo "Value found and matches expected"
 Else 
    wscript.echo "Value found but does not match expected"
 End If
