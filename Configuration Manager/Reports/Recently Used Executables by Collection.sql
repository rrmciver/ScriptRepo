SELECT [CompanyName0] as 'Publisher'
      ,[ProductName0] as 'Product Name'
      ,[ProductVersion0] as 'Product Version'
      ,[ExplorerFileName0] as 'File Name'
      ,[FileVersion0] as 'File Version'
      ,[FolderPath0] as 'File Path'
      ,[FileDescription0] as 'Description'
      ,Count([LastUserName0]) as 'Number of Users'
      ,MAX(LastUsedTime0) as 'Last Used'
  FROM v_GS_CCM_RECENTLY_USED_APPS RUA
  INNER JOIN v_FullCollectionMembership FCM on RUA.ResourceID = FCM.ResourceID
  Where DATEDIFF(day, LastUsedTime0, GETDATE()) < @lastUsed
  and ProductName0 NOT LIKE '%Operating System'
  and ProductName0 NOT LIKE '%Configuration Manager'
  and FCM.CollectionID = @colID
  Group By CompanyName0, ExplorerFileName0, FileDescription0, FileVersion0, FolderPath0,ProductName0,ProductVersion0
  Order By 'Number of Users' DESC