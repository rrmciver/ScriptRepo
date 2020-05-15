Import-Module ActiveDirectory
$ADSearchBase = "OU=Computers,DC=MyCompany,DC=COM"
[int]$LastLogonAgeDays = 30
$ADDisabled = @()
$ADStaleComp = @()
$ADUnsupportedOS = @()
$ADActive = @()
$exportDate = Get-Date -uformat "%m-%d-%Y"
$lastLogonStaleDate = (Get-Date).AddDays(-$LastLogonAgeDays)
$exportFullList = "$PSScriptRoot\GetADComputersList$exportDate.csv"
$exportStale = "$PSScriptRoot\GetADComputersStale$exportDate.csv"
$exportDisabled = "$PSScriptRoot\GetADComputersDisabled$exportDate.csv"
$exportUnsupOS = "$PSScriptRoot\GetADComputersUnsupportedOS$exportDate.csv"
$exportADActive = "$PSScriptRoot\GetADComputersActive$exportDate.csv"
$exportSummary = "$PSScriptRoot\GetADComputersSummary$exportDate.csv"
$getADComputers = Get-ADComputer -Filter * -SearchBase $ADSearchBase -Properties Enabled,LastLogonDate,PasswordLastSet,OperatingSystem,CanonicalName
$getADComputers | export-csv $exportFullList
$ADTotal = $getADComputers.Count
Write-Output "Total Number of Computer Objects in AD: $ADTotal" | Out-File $exportSummary -append
Foreach ($_ in $getADComputers)
{
    $IsActive = 1
    $obj = new-object PSObject
    $conName = $_.CanonicalName.TrimEnd($_.Name)
    if ($_.LastLogonDate -le $lastLogonStaleDate)
    {
        $obj | add-member -membertype NoteProperty -Name Name -value $_.Name
        $obj | add-member -membertype NoteProperty -Name Enabled -value $_.Enabled
        $obj | add-member -membertype NoteProperty -Name LastLogon -value $_.LastLogonDate
        $obj | add-member -membertype NoteProperty -Name OS -value $_.OperatingSystem
        $obj | add-member -membertype NoteProperty -Name OU -value $conName
        $ADStaleComp+=$obj
        $obj = new-object PSObject
        $IsActive = 0
    }
    if ($_.Enabled -ne "True")
    {
        $obj | add-member -membertype NoteProperty -Name Name -value $_.Name
        $obj | add-member -membertype NoteProperty -Name Enabled -value $_.Enabled
        $obj | add-member -membertype NoteProperty -Name LastLogon -value $_.LastLogonDate
        $obj | add-member -membertype NoteProperty -Name OS -value $_.OperatingSystem
        $obj | add-member -membertype NoteProperty -Name OU -value $conName
        $ADDisabled+=$obj
        $obj = new-object PSObject
        $IsActive = 0
    }
    if ($_.OperatingSystem -notlike "*Windows*")
    {
        $obj | add-member -membertype NoteProperty -Name Name -value $_.Name
        $obj | add-member -membertype NoteProperty -Name Enabled -value $_.Enabled
        $obj | add-member -membertype NoteProperty -Name LastLogon -value $_.LastLogonDate
        $obj | add-member -membertype NoteProperty -Name OS -value $_.OperatingSystem
        $obj | add-member -membertype NoteProperty -Name OU -value $conName
        $ADUnsupportedOS+=$obj
        $obj = new-object PSObject
        $IsActive = 0
    }
    if ($IsActive -eq 1)
    {
        $obj | add-member -membertype NoteProperty -Name Name -value $_.Name
        $obj | add-member -membertype NoteProperty -Name Enabled -value $_.Enabled
        $obj | add-member -membertype NoteProperty -Name LastLogon -value $_.LastLogonDate
        $obj | add-member -membertype NoteProperty -Name OS -value $_.OperatingSystem
        $obj | add-member -membertype NoteProperty -Name OU -value $conName
        $ADActive+=$obj
        $obj = new-object PSObject
    }
}
$ADActiveCount = $ADActive.Count
$ADStaleTotal = $ADStaleComp.Count
$ADDisabledTotal = $ADDisabled.Count
$ADUnsupportedTotal = $ADUnsupportedOS.Count
Write-Output "Total Number of Stale Computers: $ADStaleTotal" | Out-File $exportSummary -append
Write-Output "Total Number of Disabled Computers: $ADDisabledTotal" | Out-File $exportSummary -append
Write-Output "Total Number of Systems with a non-Windows OS: $ADUnsupportedTotal" | Out-File $exportSummary -append
Write-Output "Total Number of Active Computer Objects in AD: $ADActiveCount" | Out-file $exportSummary -append
$ADStaleComp | export-csv $exportStale
$ADDisabled | export-csv $exportDisabled
$ADUnsupportedOS | export-csv $exportUnsupOS
$ADActive | export-csv $exportADActive