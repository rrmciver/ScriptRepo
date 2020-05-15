START /wait "C:\Program Files\Microsoft\MDOP MBAM\MBAMClientUI.exe"
%systemroot%\sysnative\manage-bde.exe -status | findstr "Ecryption in Progress" && GOTO END
%systemroot%\sysnative\manage-bde.exe -status | findstr "TPM" && GOTO END
%systemroot%\sysnative\manage-bde.exe -protectors -disable C:
%systemroot%\sysnative\manage-bde.exe -protectors -delete C:
%systemroot%\sysnative\manage-bde.exe -protectors -add C: -recoverypassword -tpm
%systemroot%\sysnative\manage-bde.exe -protectors -enable C:
:END
EXIT /b