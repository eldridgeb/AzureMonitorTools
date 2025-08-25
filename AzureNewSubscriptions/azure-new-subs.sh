# Azure Tenant Activity Logs
# Use Azure CLI to call REST API and get tenant-level activity logs
# As per: https://learn.microsoft.com/en-us/rest/api/monitor/tenant-activity-logs/list

# Login to the correct scope
az login --scope https://management.azure.com//.default

# Get the tenant name and UPN
tenant_name=$(az account show --query tenantId -o tsv)
upn=$(az account show --query user.name -o tsv)
echo "Tenant ID: $tenant_name"
echo "User Principal Name: $upn"

# Lookback hours (default 1). Can be provided as the first positional argument or via the HOURS_AGO env var
HOURS_AGO="${1:-${HOURS_AGO:-1}}"

# Get timestamp for ${HOURS_AGO} hours ago
six_hours_ago=$(date -u -d "${HOURS_AGO} hours ago" +'%Y-%m-%dT%H:%M:%SZ')
# And for now
now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')


# Call this API: GET https://management.azure.com/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01
# Filter events between the lookback time and now
# Write to a JSON object
activity_logs=$(az rest --method get --url 'https://management.azure.com/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&$filter=eventTimestamp ge '"$six_hours_ago"' and eventTimestamp le '"$now"'')

# Filter the JSON object where EventName Value is Create and collect the full .properties objects (deduplicated)
create_events=$(echo "$activity_logs" | jq '[.value[] | select(.eventName.value == "Create") | .properties] | unique')

# Echo the number of new subscriptions created (create events)
echo "Number of new subscriptions created: $(echo "$create_events" | jq 'length')"

# Write the create events to a JSON file
echo "$create_events" > new_subs.json