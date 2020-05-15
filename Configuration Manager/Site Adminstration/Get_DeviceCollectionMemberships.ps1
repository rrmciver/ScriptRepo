Clear-Host

Start-Transcript -Path "C:\Windows\Temp\Get_CMDeviceCollectionMemberships.log" -Force

$hostname = Read-Host "Device Name"
$cmDeviceCollections = Get-WmiObject -ComputerName 'VM1'  -Namespace root/SMS/Site_CM1 -Query "SELECT SMS_Collection.* FROM SMS_FullCollectionMembership, SMS_Collection where name = '$hostname' and SMS_FullCollectionMembership.CollectionID = SMS_Collection.CollectionID"
Write-Host ""
$cmDeviceCollections.Name
Write-Host ""

Stop-Transcript
