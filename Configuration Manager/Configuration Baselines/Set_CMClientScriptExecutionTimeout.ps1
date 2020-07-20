# Sets the script execution timeout to 5 minutes or 300 seconds
Get-WMIObject -Namespace root\ccm\policy\machine\actualconfig -Class CCM_ConfigurationManagementClientConfig | Set-WMIInstance -Arguments @{ScriptExecutionTimeOut = 300}