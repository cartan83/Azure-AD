<#
This script will get the last sign-in for each user across all applications within the last 90 days. Let me know if you need further adjustments
#>
#INstall Module
Install-Module Microsoft.Graph -Scope CurrentUser -Repository PSGallery -Force

# Define the export file path
$exportPath = ".\AzureSignIns_Last90Days.csv"

# Set the time range for the last 90 days
$endDateTime = (Get-Date).ToUniversalTime()
$startDateTime = (Get-Date).AddDays(-90).ToUniversalTime()

# Connect to Microsoft Graph Beta
Connect-MgGraph -Scopes "AuditLog.Read.All"

# Query the sign-ins for all apps within the last 90 days
$signIns = Get-MgAuditLogSignIn -Filter "createdDateTime ge $($startDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')) and createdDateTime le $($endDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ'))" -All

# Group the sign-ins by userPrincipalName and select the last sign-in event for each user
$latestSignIns = $signIns | Group-Object userPrincipalName | ForEach-Object {
    $_.Group | Sort-Object createdDateTime -Descending | Select-Object -First 1
}

# Select the relevant fields
$filteredSignIns = $latestSignIns | Select-Object userDisplayName, userPrincipalName, appId, appDisplayName, createdDateTime

# Export the result to CSV
$filteredSignIns | Export-Csv -Path $exportPath -NoTypeInformation

Write-Host "Export completed. File saved to $exportPath"
