<# 
Name: Azure Log Analytics Workspace Usage
Description: Script to collect Log Analytics Workspace usage data across all Azure Subscriptions
#>

# Optional: Set TenantId to query a specific tenant - otherwise default tenant will be used
param(
[string]$TenantId
)

Start-Transcript -Path ".\AzureLogAnalyticsUsage-$(get-date -f yyyy-MM-dd-HHmm).log" -Append -Force

Write-Host "Start time: " (Get-Date)


if ($null -eq $TenantId) {
    Write-Host "Logging in to default tenant"
    az login
    $TenantId = (az account show --query tenantId -o tsv)
} else {
    Write-Host "Logging in to tenant: " $TenantId
    az login -t $TenantId
}

Write-Host "Getting all Azure Subscriptions for tenant: " $TenantId
$Subs = Get-AzSubscription -TenantId $TenantId

# Set arrays
$WorkspaceUsageResults = @()
$MappedTablesResults = @()

$UnusedWorkspaces = @()
$UnmappedTables = @()

# Query for usage summary per Log Analytics workspace
$UsageQuery = "Usage " `
+ "| where TimeGenerated > ago(30d) " `
+ "and DataType != 'Heartbeat'" `
+ "| summarize IngestionVolumeMB=sum(Quantity) by DataType"

# Loop through all Azure Subscriptions
foreach ($Sub in $Subs) {

    az account set -n $Sub.Id | Out-Null
    Write-Host "Processing Subscription:" $($Sub).name

    # Get all Log Analytics Workspaces in the subscription
    $Workspaces = az monitor log-analytics workspace list --subscription $Sub.Id --query "[].{Name:name, ResourceGroup:resourceGroup, Id:customerId}" --output json | ConvertFrom-Json

    # Loop through all Log Analytics Workspaces
    foreach ($Workspace in $Workspaces) {

        Write-Host "-- Processing Workspace:" $Workspace.Name
        
        # Query Log Analytics Workspace for all Usage
        $UsageQueryResults = az monitor log-analytics query -w $Workspace.Id --analytics-query $UsageQuery --output json | ConvertFrom-Json

        # If no results, skip to next workspace
        if ($null -eq $UsageQueryResults) {
            Write-Host "---- No results for workspace" $Workspace.Name
            $UnusedItem = [PSCustomObject]@{
                WorkspaceSubscriptionId = $Sub.Id
                WorkspaceSubscription = $Sub.Name                
                WorkspaceResourceGroup = $Workspace.ResourceGroup
                WorkspaceName = $Workspace.Name
            }
            $UnusedWorkspaces += $UnusedItem
            continue
        }

        # Loop through all Log Analytics Workspace Usage
        :labelEachUsageResult foreach ($UsageResult in $UsageQueryResults) {

            Write-Host "---- Processing DataType:" $UsageResult.DataType

            # Store all results for resource in PS Object
            $WorkspaceUsageItem = [PSCustomObject]@{
                WorkspaceSubscriptionId = $Sub.Id
                WorkspaceSubscription = $Sub.Name                
                WorkspaceResourceGroup = $Workspace.ResourceGroup
                WorkspaceName = $Workspace.Name

                DataType = $UsageResult.DataType
                IngestionVolumeMB = $UsageResult.IngestionVolumeMB
            }

            # Add PS Object to array
            $WorkspaceUsageResults += $WorkspaceUsageItem

            # Query Log Analytics Workspace for common Data Sources
            switch ($UsageResult.DataType) {
                # AzureDiagnostics table, with additional logic for Logic Apps due to how they are logged
                "AzureDiagnostics" {
                    $DataSourceQuery = $UsageResult.DataType + " " `
                    + "| where TimeGenerated > ago(30d) " `
                    + "| extend " `
                    + "ResourceType=case(ResourceProvider == 'MICROSOFT.LOGIC', 'LOGICAPPS', ResourceType), " `
                    + "Resource=case(ResourceProvider == 'MICROSOFT.LOGIC', resource_workflowName_s, Resource), " `
                    + "ResourceId=case(ResourceProvider == 'MICROSOFT.LOGIC', workflowId_s, ResourceId) " `
                    + "| summarize ResourceLogCount=count(), ResourceGB=sum(_BilledSize) / 1.E9 by SubscriptionId, ResourceGroup, Resource, ResourceProvider, ResourceType, ResourceId"
                }
                "AzureMetrics" {
                    $DataSourceQuery = $UsageResult.DataType + " " `
                    + "| where TimeGenerated > ago(30d) " `
                    + "| summarize ResourceLogCount=count(), ResourceGB=sum(_BilledSize) / 1.E9 by SubscriptionId, ResourceGroup, Resource, ResourceProvider, ResourceId"
                }
                # Storage-related tables
                {$_.StartsWith("Storage")} {
                    $DataSourceQuery = $UsageResult.DataType + " " `
                    + "| where TimeGenerated > ago(30d) " `
                    + "| summarize ResourceLogCount=count(), ResourceGB=sum(_BilledSize) / 1.E9 by _SubscriptionId, StorageAccountName=AccountName, _ResourceId"
                }
                # App-related tables
                {($_.StartsWith("App")) -or ($_.StartsWith("FunctionApp"))} {
                    $DataSourceQuery = $UsageResult.DataType + " " `
                    + "| where TimeGenerated > ago(30d) " `
                    + "| summarize ResourceLogCount=count(), ResourceGB=sum(_BilledSize) / 1.E9 by _SubscriptionId, AppRoleName, AppRoleInstance, _ResourceId"
                }
                # VM and container related tables
                {($_.StartsWith("VM")) -or ($_.StartsWith("ServiceMap")) -or ($_.StartsWith("Update")) -or ($_.StartsWith("WindowsEvent")) -or ($_.EndsWith("_CL")) `
                    -or ($_ -in ("Event", "InsightsMetrics", "Operation", "Perf", "SecurityEvents", "Syslog", "W3CIISLog")) `
                    -or ($_.StartsWith("ContainerLog")) -or ($_ -in ("ContainerInventory", "ContainerNodeInventory", "KubeEvents", "KubeMonAgentEvents", "KubeNodeInventory", "KubePodInventory", "KubePVInventory"))
                } {
                    $DataSourceQuery = $UsageResult.DataType + " " `
                    + "| where TimeGenerated > ago(30d) " `
                    + "| summarize ResourceLogCount=count(), ResourceGB=sum(_BilledSize) / 1.E9 by _SubscriptionId, Computer, _ResourceId"
                }
                # AVS-related tables
                "AVSSyslog" {
                    $DataSourceQuery = $UsageResult.DataType + " " `
                    + "| where TimeGenerated > ago(30d) " `
                    + "| summarize ResourceLogCount=count(), ResourceGB=sum(_BilledSize) / 1.E9 by _SubscriptionId, HostName, _ResourceId"
                }
                # Defender for Endpoint tables
                {$_.StartsWith("Device")} {
                    $DataSourceQuery = $UsageResult.DataType + " " `
                    + "| where TimeGenerated > ago(30d) " `
                    + "| summarize ResourceLogCount=count(), ResourceGB=sum(_BilledSize) / 1.E9 by DeviceName, DeviceId"
                }
                # MCAS tables
                "CloudAppEvents" {
                    $DataSourceQuery = $UsageResult.DataType + " " `
                    + "| where TimeGenerated > ago(30d) " `
                    + "| summarize ResourceLogCount=count(), ResourceGB=sum(_BilledSize) / 1.E9 by Application, ApplicationId"
                }
                default {
                    Write-Host "------ TABLE UNMAPPED: " $UsageResult.DataType " MB: " $UsageResult.IngestionVolumeMB
                    $UnmappedItem = [PSCustomObject]@{
                        WorkspaceSubscriptionId = $Sub.Id
                        WorkspaceSubscription = $Sub.Name                
                        WorkspaceResourceGroup = $Workspace.ResourceGroup
                        WorkspaceName = $Workspace.Name
                        DataType = $UsageResult.DataType
                        IngestionVolumeMB = $UsageResult.IngestionVolumeMB
                    }
                    $UnmappedTables += $UnmappedItem
                    continue labelEachUsageResult
                }
            }

            Write-Host "------ TABLE: " $UsageResult.DataType " MB: " $UsageResult.IngestionVolumeMB
            $DataSourceQueryResults = az monitor log-analytics query -w $Workspace.Id --analytics-query $DataSourceQuery --output json | ConvertFrom-Json
            Write-Host "------ QUERY DONE"

            # Loop through common Log Analytics Workspace Data Sources
            foreach ($DataSourceResult in $DataSourceQueryResults) {

                if ($null -ne $DataSourceResult.Resource) {
                    Write-Host "-------- Processing Resource: " $DataSourceResult.Resource
                } elseif ($null -ne $DataSourceResult.Computer) {
                    Write-Host "-------- Processing Computer: " $DataSourceResult.Computer
                } elseif ($null -ne $DataSourceResult.AppRoleName) {
                    Write-Host "-------- Processing AppRoleName: " $DataSourceResult.AppRoleName
                } elseif ($null -ne $DataSourceResult.StorageAccountName) {
                    Write-Host "-------- Processing StorageAccountName: " $DataSourceResult.StorageAccountName
                } elseif ($null -ne $DataSourceResult.DeviceName) {
                    Write-Host "-------- Processing DeviceName: " $DataSourceResult.DeviceName
                } elseif ($null -ne $DataSourceResult.HostName) {
                    Write-Host "-------- Processing HostName: " $DataSourceResult.HostName
                } elseif ($null -ne $DataSourceResult.Application) {
                    Write-Host "-------- Processing Application: " $DataSourceResult.Application
                } else {
                    Write-Host "-------- Processing unknown datasource from table: " $UsageResult.DataType 
                }

                # Store all results for resource in PS Object
                $MappedTableItem = [PSCustomObject]@{
                    WorkspaceSubscriptionId = $Sub.Id
                    WorkspaceSubscription = $Sub.Name                
                    WorkspaceResourceGroup = $Workspace.ResourceGroup
                    WorkspaceName = $Workspace.Name

                    Table = $UsageResult.DataType

                    # Common fields
                    ResourceSubscriptionId = if ($null -eq $DataSourceResult.SubscriptionId) { $DataSourceResult._SubscriptionId } else { $DataSourceResult.SubscriptionId }
                    ResourceSubscription = $DataSourceResult.SubscriptionId
                    ResourceResourceGroup = $DataSourceResult.ResourceGroup
                    ResourceName = $DataSourceResult.Resource
                    ResourceProvider = $DataSourceResult.ResourceProvider
                    ResourceId = if ($null -eq $DataSourceResult.ResourceId) { $DataSourceResult._ResourceId } else { $DataSourceResult.ResourceId }

                    # Fields for AzureDiagnostics table
                    ResourceType = $DataSourceResult.ResourceType

                    # Fields for Storage tables
                    StorageAccountName = $DataSourceResult.StorageAccountName

                    # Fields for App tables
                    AppRoleName = $DataSourceResult.AppRoleName
                    AppRoleInstance = $DataSourceResult.AppRoleInstance

                    # Fields for VM and container tables
                    Computer = $DataSourceResult.Computer

                    # Fields for AVS tables
                    HostName = $DataSourceResult.HostName

                    # Fields for Defender for Endpoint tables
                    DeviceName = $DataSourceResult.DeviceName
                    DeviceId = $DataSourceResult.DeviceId

                    # Fields for MCAS tables
                    Application = $DataSourceResult.Application
                    ApplicationId = $DataSourceResult.ApplicationId

                    ResourceLogCount = $DataSourceResult.ResourceLogCount
                    ResourceGB = $DataSourceResult.ResourceGB
                }

                # Add PS Object to array
                $MappedTablesResults += $MappedTableItem
            }

        }
    }
}

# Save results to CSV as tabular data with timestamps
$WorkspaceUsageResults | Export-Csv -Force -Path ".\AzureLogAnalytics-WorkspaceUsage-$(get-date -f yyyy-MM-dd-HHmm).csv"
$MappedTablesResults | Export-Csv -Force -Path ".\AzureLogAnalytics-MappedTables-$(get-date -f yyyy-MM-dd-HHmm).csv"
$UnusedWorkspaces | Export-Csv -Force -Path ".\AzureLogAnalytics-UnusedWorkspaces-$(get-date -f yyyy-MM-dd-HHmm).csv"
$UnmappedTables | Export-Csv -Force -Path ".\AzureLogAnalytics-UnmappedTables-$(get-date -f yyyy-MM-dd-HHmm).csv"

# Save results to CSV as tabular data without timestamps (to read in Power BI, etc.)
$WorkspaceUsageResults | Export-Csv -Force -Path ".\AzureLogAnalytics-WorkspaceUsage.csv"
$MappedTablesResults | Export-Csv -Force -Path ".\AzureLogAnalytics-MappedTables.csv"
$UnusedWorkspaces | Export-Csv -Force -Path ".\AzureLogAnalytics-UnusedWorkspaces.csv"
$UnmappedTables | Export-Csv -Force -Path ".\AzureLogAnalytics-UnmappedTables.csv"

Write-Host "All done."

Stop-Transcript