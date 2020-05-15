SELECT vrs.Name0 as "Computer Name"
,Client0 as "SCCM Client"
,vrs.User_Name0 as "Last Known User"
,TopConsoleUser0 as "Top Console User"
,gos.Caption0 as "Operating System Name"
,CSDVersion0 as "Service Pack"
,gos.Version0 as "OS Version Number"
,gcs.Manufacturer0 as "Hardware Make"
,Model0 as "Hardware Model"
,bios.SerialNumber0 as 'Serial Number'
,bios.SerialNumber0 as 'Serial Number'
,bios.SMBIOSBIOSVersion0 as "BIOS Version"
,nac.IPAddress0 as "Last Known IP Address"
,MAX(System_OU_Name0) as "OU Name"
  FROM v_R_System vrs
  LEFT JOIN v_GS_SYSTEM_CONSOLE_USAGE_MAXGROUP tcu on vrs.ResourceID = tcu.ResourceID
  LEFT JOIN v_GS_COMPUTER_SYSTEM gcs on gcs.ResourceID = vrs.ResourceID
  LEFT JOIN v_GS_OPERATING_SYSTEM gos on gos.ResourceID = vrs.ResourceID
  LEFT JOIN v_RA_System_SystemOUName sou on sou.ResourceID = vrs.ResourceID
  LEFT JOIN v_GS_PC_BIOS BIOS on VRS.ResourceID = BIOS.ResourceID
  LEFT JOIN v_GS_NETWORK_ADAPTER_CONFIGURATION nac on VRS.ResourceID = nac.ResourceID
  INNER JOIN v_FullCollectionMembership fcm on fcm.ResourceID = vrs.ResourceID
  WHERE CollectionID = @colID AND DNSDomain0 = 'contoso.com' AND ServiceName0 not like 'NETw%'
  GROUP BY vrs.Name0, Active0, Client0, vrs.User_Name0, TopConsoleUser0, gcs.Manufacturer0, Model0, gos.Caption0, CSDVersion0, gos.Version0, bios.SMBIOSBIOSVersion0, bios.SerialNumber0, nac.IPAddress0
  Order By vrs.Name0