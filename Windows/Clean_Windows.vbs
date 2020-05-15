'Clean Windows
'This script can be run as needed to clean up supported areas of the C: drive and reclaim disk space.
'Clears the Windows Update download cache, Windows Temp folder, and SCCM Client cache.

on error resume next 
dim oUIResManager 
dim oCache 
dim oCacheElement 
dim oCacheElements 
strServiceName = "wuauserv"
set fso = CreateObject("Scripting.FileSystemObject")
Set objShell = WScript.CreateObject("Wscript.Shell")
Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
objShell.Run "net stop wuauserv /yes" ,0, True
'wscript.echo "Cleaning up Windows Update download cache"
fso.DeleteFile("C:\Windows\SoftwareDistribution\Download\*"), DeleteReadOnly
fso.DeleteFolder("C:\Windows\SoftwareDistribution\Download\*"), DeleteReadOnly
'wscript.echo "Starting Windows Update service"
objShell.Run "net start wuauserv", 0, True
'wscript.echo "Cleaning up Windows Temp folder"
fso.DeleteFile("C:\Windows\Temp\*"), DeleteReadOnly
fso.DeleteFolder("C:\Windows\Temp\*"), DeleteReadOnly
'wscript.echo "Cleaning up SCCM download cache"
set oUIResManager = createobject("UIResource.UIResourceMgr") 
if oUIResManager is nothing then 
      wscript.echo "Couldn't create Resource Manager" 
end if 
set oCache=oUIResManager.GetCacheInfo() 
if oCache is nothing then 
     set oUIResManager=nothing 
      wscript.echo "Couldn't get cache info"
end if 
set oCacheElements=oCache.GetCacheElements 
'wscript.echo "There are " & oCacheElements.Count & " cache elements" 
' ***** Begin CLEAR CACHE ***** 
for each oCacheElement in oCacheElements 
oCache.DeleteCacheElement(oCacheElement.CacheElementID) 
next 
'wscript.echo "***** End CLEAN *****"
' ***** Clean up ***** 
set oCacheElements=nothing 
set oUIResManager=nothing 
set oCache=nothing 
