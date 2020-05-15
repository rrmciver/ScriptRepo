/* Computer Members */
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
	  ,MAX(System_OU_Name0) as 'Computer OU'
  FROM v_R_System VRS
  INNER JOIN v_GS_OPERATING_SYSTEM OS on VRS.ResourceID = OS.ResourceID
  INNER JOIN v_GS_COMPUTER_SYSTEM CS on VRS.ResourceID = CS.ResourceID
  INNER JOIN v_RA_System_SystemGroupName SGN ON VRS.ResourceID = SGN.ResourceID
  LEFT JOIN v_R_User USR on VRS.User_Name0 = USR.User_Name0
  LEFT JOIN v_RA_System_SystemOUName OU on VRS.ResourceID = OU.ResourceID
  WHERE (Resource_Domain_OR_Workgr0 = Windows_NT_Domain0 OR Windows_NT_Domain0 IS NULL) AND System_Group_Name0 = @groupName
  Group By Netbios_Name0, Full_User_Name0, VRS.User_Name0, VRS.Resource_Domain_OR_Workgr0, CS.Manufacturer0, CS.Model0, OS.Caption0, CSDVersion0, BuildNumber0, OS.InstallDate0, 
  Last_Logon_Timestamp0, Client_Version0
  ORDER BY Netbios_Name0

  /* User Members */
  SELECT 
      [Full_User_Name0] as 'User Full Name'
	  ,[Windows_NT_Domain0] as 'Domain'
      ,[User_Name0] as 'User Name'
	  ,CAST(([lastLogonTimestamp0] / 864000000000.0 - 109207) as DATETIME) as 'Last Domain Logon'
	  ,MAX(User_OU_Name0) as 'User OU'
  FROM v_R_User VRU
  INNER JOIN v_RA_User_UserGroupName UGN ON VRU.ResourceID = UGN.ResourceID
  LEFT JOIN v_RA_User_UserOUName UOU on VRU.ResourceID = UOU.ResourceID
  WHERE User_Group_Name0 = @groupName
  GROUP BY Full_User_Name0, Windows_NT_Domain0, User_Name0, lastLogonTimestamp0
ORDER BY Full_User_Name0

/* Groups */
SELECT USR.User_Group_Name0 as 'Group Name'
FROM
(SELECT DISTINCT
	User_Group_Name0
   FROM v_RA_User_UserGroupName UG
   INNER JOIN v_R_User VRU ON UG.ResourceID = VRU.ResourceID) USR
UNION
SELECT DVC.System_Group_Name0 as 'Group Name'
FROM
(SELECT DISTINCT
      System_Group_Name0
  FROM v_RA_System_SystemGroupName SGN
  INNER JOIN v_R_SYSTEM VRS ON SGN.ResourceID = VRS.ResourceID) DVC
  ORDER BY 'Group Name'