#Variables
<#TenantID : Provide the tenantID of your subscription
GraphAppId : This parameter is optional. We don’t have to change this value. This corresponds to Graph API Guid.
DisplayNameofMSI :  Provide your Logic App name. Since managed identity will be created in the same name as the resource on which identity is enabled, we can provide the Logic App name
Permissions : Provide the appropriate Graph API Permission. https://docs.microsoft.com/en-us/graph/permissions-reference. Note: These are application permission.
#>
#Vaiables:
$TenantID="972c0821-fe2d-4379-b6e8-acd0c3427548"
$GraphAppId = "00000003-0000-0000-c000-000000000000"
$DisplayNameOfMSI="AA-BitlockerKeyRotation"
$PermissionName = "DeviceManagementManagedDevices.ReadWrite.All"

# Install the module

Install-Module AzureAD

Connect-AzureAD -TenantId $TenantID

$MSI = (Get-AzureADServicePrincipal -Filter "displayName eq '$DisplayNameOfMSI'")
Start-Sleep -Seconds 10

$GraphServicePrincipal = Get-AzureADServicePrincipal -Filter "appId eq '$GraphAppId'"

$AppRole = $GraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $PermissionName -and $_.AllowedMemberTypes -contains "Application"}

New-AzureAdServiceAppRoleAssignment -ObjectId $MSI.ObjectId -PrincipalId $MSI.ObjectId -ResourceId $GraphServicePrincipal.ObjectId -Id $AppRole.Id