SELECT DISTINCT APP.Manufacturer
,APP.DisplayName
,APP.SoftwareVersion
,DT.DisplayName
,DeploymentTypeName
,DT.PriorityInLatestApp
,DT.Technology
,v_ContentInfo.ContentSource
,v_ContentInfo.SourceSize
FROM fn_ListDeploymentTypeCIs(1033) as dt
INNER JOIN dn_ListLatestAplicationCIs(1033) AS App ON dt.AppModelNAme = app.ModelName
LEFT OUTER JOIN v_ContentInfo ON dt.ContentID = v_ContentInfo.Content_UniqueID
WHERE (dt.IsLatest = 1)