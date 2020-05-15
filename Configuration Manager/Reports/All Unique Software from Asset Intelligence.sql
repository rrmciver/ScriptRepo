SELECT DISTINCT
      [NormalizedPublisher] as 'Publisher'       
      ,[ARPDisplayName0] as 'ARP Display Name'
      ,[ProductName0]  as 'Product Name'
      ,[ProductVersion0] as 'Version'
      ,[FamilyName] as 'Family Name'
      ,[CategoryName] as 'Category Name'
      ,[ProductCode0] as 'Product Code'
      ,[UninstallString0] as 'Uninstall String'
  FROM v_GS_INSTALLED_SOFTWARE_CATEGORIZED
  WHERE CategoryName <> 'Operating System and Components'