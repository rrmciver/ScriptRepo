%systemroot%\sysnative\manage-bde.exe -off C:
:CheckStatus
ping 127.0.0.1 -n 120 > nul
%systemroot%\sysnative\manage-bde.exe -status | findstr "Decryption in Progress" && GOTO CHECKSTATUS
%systemroot%\sysnative\manage-bde.exe -on C:
