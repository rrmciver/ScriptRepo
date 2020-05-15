Select VRS.Name0 as 'Name'
,GSD.Index0 as 'Index'
,GSD.Model0 as 'Model'
,PME.SerialNumber0 as 'Serial Number'
,GSD.Partitions0 as 'Partitions'
,GSD.Size0 as 'Size'
From v_GS_PHYSICAL_MEDIA PME
INNER JOIN v_R_System VRS on VRS.REsourceID = PME.ResourceID
INNER JOIN v_GS_Disk GSD on PME.ResourceID = GSD.ResourceID
Where GSD.DeviceID0 = PME.Tag0 AND VRS.Name0 like @cName AND GSD.Model0 not like '%VMware%'
Order By VRS.Name0