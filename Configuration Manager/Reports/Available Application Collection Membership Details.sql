/* Devices */
SELECT 
      [Netbios_Name0] as 'Computer Name'
	  ,CASE WHEN Full_User_Name0 IS NULL AND VRS.User_Name0 IS NULL THEN 'N/A' 
	  WHEN Full_User_Name0 IS NULL THEN VRS.User_Name0
	  ELSE Full_User_Name0
	  END AS 'User Name'
	  ,VRS.Resource_Domain_OR_Workgr0 as 'Domain'
	  ,CS.Manufacturer0 as 'Make'
	  ,CS.Model0 as 'Model'
	  ,OS.Caption0 as 'Operating System'
	  ,[CSDVersion0] as 'Service Pack'
	  ,[BuildNumber0] as 'OS Build Number'
	  ,FORMAT(OS.InstallDate0, 'MM-dd-yyyy hh:mm:ss tt') as 'OS Install Date'
	  ,FORMAT([Last_Logon_Timestamp0], 'MM-dd-yyyy hh:mm:ss tt') as 'Last Domain Logon'
	  ,[Client_Version0] as 'SCCM Client Version'
	  ,CollectionType as 'Collection Type'
	  ,MAX(System_OU_Name0) as 'OU'
  FROM v_R_System VRS
  INNER JOIN v_GS_OPERATING_SYSTEM OS on VRS.ResourceID = OS.ResourceID
  INNER JOIN v_GS_COMPUTER_SYSTEM CS on VRS.ResourceID = CS.ResourceID
  LEFT JOIN v_R_User USR on VRS.User_Name0 = USR.User_Name0
  INNER JOIN v_FullCollectionMembership FCM on VRS.ResourceID = FCM.ResourceID
  INNER JOIN v_Collections COL on FCM.CollectionID = COL.SiteID
  LEFT JOIN v_RA_System_SystemOUName OU on VRS.ResourceID = OU.ResourceID
  WHERE (Resource_Domain_OR_Workgr0 = Windows_NT_Domain0 OR Windows_NT_Domain0 IS NULL) AND FCM.CollectionID = @colID
  Group By Netbios_Name0, Full_User_Name0, VRS.User_Name0, VRS.Resource_Domain_OR_Workgr0, CS.Manufacturer0, CS.Model0, OS.Caption0, CSDVersion0, BuildNumber0, OS.InstallDate0, 
  Last_Logon_Timestamp0, Client_Version0, CollectionType
  ORDER BY Netbios_Name0

  /* Collections */
Select SiteID, CollectionName, CollectionType
FROM v_Collections
WHERE MemberCount > 0
ORDER BY CollectionName

/* Users */
SELECT 
      [Full_User_Name0] as 'User Full Name'
	  ,[Windows_NT_Domain0] as 'Domain'
      ,[User_Name0] as 'User Name'
	  ,CAST(([lastLogonTimestamp0] / 864000000000.0 - 109207) as DATETIME) as 'Last Domain Logon'
	  ,CollectionType
	  ,MAX(User_OU_Name0) as 'OU'
  FROM v_R_User VRU
  INNER JOIN v_FullCollectionMembership FCM on VRU.ResourceID = FCM.ResourceID
  INNER JOIN v_Collections COL on FCM.CollectionID = COL.SiteID
  LEFT JOIN v_RA_User_UserOUName UOU on VRU.ResourceID = UOU.ResourceID
  WHERE FCM.CollectionID = @colID
  GROUP BY Full_User_Name0, Windows_NT_Domain0, User_Name0, lastLogonTimestamp0, CollectionType
ORDER BY Full_User_Name0

