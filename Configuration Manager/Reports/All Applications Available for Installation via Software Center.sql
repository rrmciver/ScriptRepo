Select PKGS.Name as 'Application Name', 'Package' as 'Type'
FROM
	(SELECT PKG.Name, ProgramName, CollectionName
	FROM v_Advertisement ADV
	LEFT JOIN v_Package PKG ON ADV.PackageID = PKG.PackageID
	LEFT JOIN v_Collections COL ON ADV.CollectionID = COL.SiteID
	WHERE COL.MemberCount > '0' AND AssignedScheduleEnabled = '0' AND PackageType = '0' AND PresentTimeEnabled = '1' AND PresentTime <= GetDate() AND (ExpirationTimeEnabled = '0' OR ExpirationTime > GetDate())
	) PKGS
  UNION
Select APPS.ApplicationName as 'Application Name', 'Application' as 'Type'
FROM
	(SELECT AA.ApplicationName
	FROM v_ApplicationAssignment AA
	LEFT JOIN v_Collections COL on AA.CollectionID = COL.SiteID
	WHERE COL.MemberCount > '0' AND EnforcementDeadline IS NULL AND StartTime <= GetDate() AND (ExpirationTime IS NULL OR ExpirationTime > GetDate())
	) APPS
ORDER BY 'Application Name'