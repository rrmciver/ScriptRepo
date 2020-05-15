SET PACKAGEID=CM100027
C:\Windows\Sysnative\cmd.exe /c xcopy /y /i "%~dp0runTS.ps1" C:\Windows\System32
C:\Windows\Sysnative\schtasks.exe /create /RU Administrators /RP /SC ONLOGON /TN "Run Task Sequence On Logon" /TR "\"C:\Windows\System32\WindowsPowerShell\v1.0\Powershell.exe\" -executionpolicy bypass -file \"C:\Windows\System32\runTS.ps1\" %PACKAGEID%" /F /RL HIGHEST