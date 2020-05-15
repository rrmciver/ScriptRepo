Select Name0 as 'Computer Name'
,ARPDisplayName0 as 'ARP Display Name'
,ProductName0 as 'Product Name'
,Publisher0 as 'Publisher'
,ProductVersion0 as 'Version'
,InstalledLocation0 as 'Installed Location'
,InstallDate0 as 'Install Date'
,InstallSource0 as 'Install Source'
,LastHWScan as 'Last Inventory Scan'
From v_R_System vrs
LEFT JOIN v_GS_INSTALLED_SOFTWARE arp on vrs.ResourceID = arp.ResourceID
LEFT JOIN v_GS_WORKSTATION_STATUS wss on vrs.ResourceID = wss.ResourceID
INNER JOIN v_FullCollectionMembership fcm on vrs.ResourceID = fcm.ResourceID
WHERE fcm.CollectionID = @colID
Order By Name0