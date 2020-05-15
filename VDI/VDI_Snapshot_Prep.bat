REM VDI_Snapshot_PREP
REM Reference: https://www.ituda.com/vmware-horizon-view-recomposing-dont-forget-to-cleanup-after-you-finished/
REM The script should be run as the last step before shutting down and snapshotting a gold-master Windows VM for replication.
REM Be sure to manually run cleanmgr /sageset:1 to create a disk cleanup profile first

REM Execute queued .NET Framework compilation jobs
C:\Windows\Microsoft.NET\Framework\v2.0.50727\ngen.exe executeQueuedItems
C:\Windows\Microsoft.NET\Framework64\v2.0.50727\ngen.exe executeQueuedItems
REM Disable the Windows Update service
sc stop wuauserv
sc config wuauserv start= disabled
sc config svservice start= auto
REM Delete Shadow Copies
vssadmin delete shadows /All /Quiet
REM Clear the Windows Update download cache
del c:\Windows\SoftwareDistribution\Download\*.* /f /s /q
REM Delete hidden install files
del %windir%\$NT* /f /s /q /a:h
REM Delete prefetch files
del c:\Windows\Prefetch\*.* /f /s /q
REM Run disk cleanup
c:\windows\system32\cleanmgr /sagerun:1
REM Run disk defrag
sc config defragsvc start= auto
net start defragsvc
defrag c: /U /V
net stop defragsvc
sc config defragsvc start = disabled
REM Rearm Office activation (Office 2016)
"C:\Program Files (x86)\Microsoft Office\Office16\OSPPREARM.exe"
REM Clear Windows event logs
wevtutil el 1>a.txt
for /f %%x in (a.txt) do wevtutil cl %%x
del a.txt
REM Flush DNS cache and release IP address, then shutdown
ipconfig /release
ipconfig /flushdns
shutdown -s -f -t 15