'Checks for an installed Microsoft update by article number.

strComputer = "."
strHotfixID = "4020302"
Set objWMIService = GetObject("winmgmts:" _
	& "{impersonationLevel=impersonate}!\\" & strComputer & "\root\cimv2")
if err.number <> 0 then
	wscript.quit
end if

strQuery = "select * from Win32_QuickFixEngineering where HotFixID = 'Q" & strHotfixID & "' OR HotFixID = 'KB" & strHotfixID & "'"
Set colQuickFixes = objWMIService.ExecQuery (strQuery)
if err.number <> 0 then
	'wscript.echo "ERROR: unable to get installed hotfix information"
else
	intCount = colQuickFixes.Count
	if intCount > 0 then
		wscript.echo "Hotfix found"
	else
		wscript.echo "Hotfix not found"
	end if
end if