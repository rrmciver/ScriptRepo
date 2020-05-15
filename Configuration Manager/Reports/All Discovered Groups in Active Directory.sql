SELECT USR.User_Group_Name0 as 'Group Name', 'User' as 'Membership Type'
FROM
(SELECT DISTINCT
	User_Group_Name0
   FROM v_RA_User_UserGroupName UG
   INNER JOIN v_R_User VRU ON UG.ResourceID = VRU.ResourceID) USR
UNION
SELECT DVC.System_Group_Name0 as 'Group Name', 'Computer' as 'Membership Type'
FROM
(SELECT DISTINCT
      System_Group_Name0
  FROM v_RA_System_SystemGroupName SGN
  INNER JOIN v_R_SYSTEM VRS ON SGN.ResourceID = VRS.ResourceID) DVC
  ORDER BY 'Group Name'