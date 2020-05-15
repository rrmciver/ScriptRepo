$FoD_Source = "C:\Temp\RSAT_1809_en-US"

#Grab the available RSAT Features

$RSAT_FoD = Get-WindowsCapability -Online | Where-Object Name -like 'RSAT*'

#Install RSAT Tools

Foreach ($RSAT_FoD_Item in $RSAT_FoD)

{

Add-WindowsCapability -Online -Name $RSAT_FoD_Item.name -Source $FoD_Source -LimitAccess

} 