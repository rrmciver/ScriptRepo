SELECT vrs.Name0 as "Computer Name"
,vrs.User_Name0 as "Last Known User"
,TopConsoleUser0 as "Top Console User"
,gcs.Manufacturer0 as "Hardware Make"
,Model0 as "Hardware Model"
,gos.Caption0 as "Operating System Name"
,arp.ARPDisplayName0 as "Installed Software"
,nac.IPAddress0 as "IP Address"
,MAX(System_OU_Name0) as "OU Name"
  FROM v_R_System vrs
  LEFT JOIN v_GS_SYSTEM_CONSOLE_USAGE_MAXGROUP tcu on vrs.ResourceID = tcu.ResourceID
  LEFT JOIN v_GS_COMPUTER_SYSTEM gcs on vrs.ResourceID = gcs.ResourceID
  LEFT JOIN v_GS_OPERATING_SYSTEM gos on vrs.ResourceID = gos.ResourceID
  LEFT JOIN v_RA_System_SystemOUName sou on vrs.ResourceID = sou.ResourceID 
  LEFT JOIN v_GS_INSTALLED_SOFTWARE arp on vrs.ResourceID = arp.ResourceID
  LEFT JOIN v_GS_NETWORK_ADAPTER_CONFIGURATION nac on vrs.ResourceID = nac.ResourceID
  WHERE (ARPDisplayName0 like 'Microsoft Office Professional%' OR ARPDisplayName0 like 'Microsoft Office 365%' OR ARPDisplayName0 like 'Microsoft Office Basic%'
  OR ARPDisplayName0 like 'Microsoft Office Personal%' OR ARPDisplayName0 like 'Microsoft Office Small Business%' OR ARPDisplayName0 like 'Microsoft Office Standard%' 
  OR ARPDisplayName0 like 'Microsoft Office Ultimate%' OR ARPDisplayName0 like 'Microsoft Office Home%') AND ARPDisplayName0 NOT LIKE '%Primary Interop%' AND ARPDisplayName0 NOT LIKE '%Web Components' AND DNSDomain0 = 'towson.edu' AND ServiceName0 not like 'NETw%'
  GROUP BY vrs.Name0, Active0, Client0, vrs.User_Name0, TopConsoleUser0, gcs.Manufacturer0, Model0, gos.Caption0, CSDVersion0, Version0, ARPDisplayName0, IPAddress0, ServiceName0
  Order By vrs.Name0