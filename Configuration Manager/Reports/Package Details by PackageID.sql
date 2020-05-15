SELECT [PackageID] as 'Package ID'
      ,[Name] as 'Package Name'
      ,[Version] as 'Product Version'
      ,[Manufacturer]
      ,[Description]
      ,[PkgSourcePath] as 'Source Path'
      ,[SourceVersion] as 'Source Version'
      ,[SourceDate] as 'Source Date'
      ,[LastRefreshTime] as 'Last Refresh'
      ,[PackageType] as 'Package Type'
  FROM v_Package
  where PackageID = @pkgID