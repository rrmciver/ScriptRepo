SELECT vrs.Name0 as 'Computer Name'
	,gos.Caption0 as 'Operating System Name'
	,gos.CSDVersion0 as 'Service Pack'
	,User_Name0 as 'Last Known User'
	,TopConsoleUser0 as 'Top Console User'
	,gcs.Manufacturer0 as 'Make'
	,Model0 as 'Model'
	,MAX(System_OU_Name0) as 'OU Name'
  FROM v_R_System vrs
  INNER JOIN v_GS_OPERATING_SYSTEM gos on vrs.ResourceID = gos.ResourceID
  INNER JOIN v_FullCollectionMembership fcm on vrs.ResourceID = fcm.ResourceID
  LEFT JOIN v_GS_SYSTEM_CONSOLE_USAGE_MAXGROUP tcu on vrs.ResourceID = tcu.ResourceID
  LEFT JOIN v_RA_System_SystemOUName sou on vrs.ResourceID = sou.ResourceID
  LEFT JOIN v_GS_COMPUTER_SYSTEM gcs on vrs.ResourceId = gcs.ResourceID
  WHERE gos.Caption0 like @OSName and CollectionID = @colID
  GROUP BY vrs.Name0,gos.Caption0,CSDVersion0,User_Name0,TopConsoleUser0, gcs.Manufacturer0,Model0
  ORDER BY vrs.Name0