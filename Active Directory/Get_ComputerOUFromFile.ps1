Import-Module ActiveDirectory
$arrComputerNames = Import-csv C:\temp\getOU.txt
ForEach ($_ in $arrComputerNames)
{
    $strName = $_.Name
    $strCanonName = Get-ADComputer $strName -property CanonicalName | Select CanonicalName | Export-Csv -Path "C:\Temp\getOUOut.csv" -append
}