Import-Module ActiveDirectory
$ADSearchBase1 = "OU=Computers,DC=MyCompany,DC=COM"

Get-ADComputer -Filter * -SearchBase $ADSearchBase | Select-Object Name | Out-File -Encoding ascii -append C:\Temp\ComputersInOU.txt
