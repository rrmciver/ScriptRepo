@Echo Off
SET /P DRIVE=Enter driver letter to decrypt (example C:):
%systemroot%\sysnative\manage-bde.exe -off %DRIVE%
EXIT /b %ERRORLEVEL%
