SELECT VRS.Name0 as 'Computer Name'
	  ,[Account0] as 'Name'
	  ,Category0 as 'Category'
	  ,[Type0] as 'Account Type'
	  ,LGM.[TimeStamp] as 'Account Last Logon'
	  ,[LastHWScan] as 'Last Inventory Update'
  FROM v_GS_LocalGroupMembers0 LGM
  INNER JOIN v_R_System VRS on LGM.ResourceID = VRS.ResourceID
  INNER JOIN v_FullCollectionMembership FCM on VRS.ResourceID = FCM.ResourceID
  LEFT JOIN v_GS_WORKSTATION_STATUS GWS on VRS.ResourceID = GWS.ResourceID
  WHERE LGM.Name0 = 'Administrators' 
AND CollectionID like @colID
ORDER BY VRS.Name0