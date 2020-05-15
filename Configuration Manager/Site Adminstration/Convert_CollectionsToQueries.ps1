$siteCode = "CM1"

$getCollections = Get-CMDeviceCollection | Where-Object {$_.CollectionRules -AND !($_.CollectionID -LIKE "SMS*") }

ForEach ($collection IN $getCollections)
{
    $getQuery = Get-CMCollectionQueryMembershipRule -CollectionID $collection.CollectionID
    ForEach ($query in $getQuery)
    {
        $queryName = "($($collection.CollectionID)) $($collection.Name)_$($query.RuleName)"
        New-CMQuery -Name $queryName -TargetClassName 'SMS_R_SYSTEM' -LimitToCollectionId $collection.LimitToCollectionID -Expression $query.QueryExpression -Comment "Created by Collection2Query utility" | Move-CMObject -FolderPath $($siteCode):\Query\Collections2Queries
    }
}