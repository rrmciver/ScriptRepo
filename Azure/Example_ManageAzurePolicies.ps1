login-azurermaccount

$resGroup = Get-AzureRMGroup -name "MY_LAB"

$policyDef = Get-AzureRMPolicyDefinition | ?{$_.Properties.DisaplyName -eq "Audit VMs that do not use managed disks"}

New-AzureRMPolicyAssignment -Name "Check for managed disks" -DisplayName "Check for managed disks" -scope $resGroup.ResourceID -PolicyDefinition $policyDef

Get-AzPolicyState -ResourceGroupName $resGroup.ResourceGroupName -PolicyAssignmentName 'Check for managed disks' -Filter 'IsCompliant eq false'