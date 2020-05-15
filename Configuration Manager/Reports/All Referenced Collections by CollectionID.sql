SELECT Distinct vCol.[CollectionID] as 'Collection ID'
      ,vCol.[Name] as 'Collection Name'
      ,vCDep.SourceCollectionID as 'Collection Dependency'
      ,vCo2.Name as 'Collection Dependency Name'
      ,Case When
	  vCDep.relationshiptype = 1 then 'Limited To - ' + vCo2.Name + ' ('+ vCDep.SourceCollectionID +')'
	  when vCDep.relationshiptype = 2 then 'Include - ' + vCo2.Name + ' ('+ vCDep.SourceCollectionID+')'
	  when vCDep.relationshiptype = 3 then 'Exclude - ' + vCo2.Name + ' ('+ vCDep.SourceCollectionID+')'
	  end as 'Relationship Type'
  FROM v_Collection vCol
  JOIN vSMS_CollectionDependencies vCDep on vCDep.DependentCollectionID = vCol.CollectionID
  JOIN v_Collection vCo2 on vCo2.CollectionID = vCDep.SourceCollectionID
  Where vCol.CollectionID = @colID
Order By 'Relationship Type'