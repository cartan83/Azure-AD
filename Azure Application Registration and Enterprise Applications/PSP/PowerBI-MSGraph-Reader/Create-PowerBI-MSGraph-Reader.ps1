<#
This script will:

Create a new Azure AD App Registration.
Assign Microsoft Graph API permissions (User.Read.All and Group.Read.All).
Generate a client secret and output it securely (ensure you save this immediately).
Output the Tenant ID, Client ID, and Client Secret.
Important Notes
Run this script with an account that has permissions to create Azure AD apps and consent to permissions.
Replace $ClientSecretDescription and $AppName with values relevant to your organization if needed.
Save the client secret securely since it won't be retrievable after creation. Consider using Azure Key Vault for secure storage.

#>
# Define variables
$AppName = "PowerBI-MSGraph-Reader"
$ClientSecretDescription = "ConsultantAccess"
$TenantId = (Get-AzTenant).Id

# Login to Azure
Connect-AzAccount

# Create App Registration
$App = New-AzADApplication -DisplayName $AppName

# Output App ID
$ClientId = $App.AppId
Write-Output "App Registration created with Client ID: $ClientId"

# Create Service Principal
$ServicePrincipal = New-AzADServicePrincipal -ApplicationId $ClientId

# Install Microsoft Graph PowerShell module if not already installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module -Name Microsoft.Graph -Force -AllowClobber
}
Import-Module Microsoft.Graph

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All"

# Add API Permissions (Microsoft Graph - Application Permissions)
$GraphServicePrincipal = Get-MgServicePrincipal -Filter "DisplayName eq 'Microsoft Graph'"
$GraphAppRoles = $GraphServicePrincipal.AppRoles

$GraphPermissions = @(
    "User.Read.All", # Read all users' full profiles
    "Group.Read.All" # Read all groups
)

foreach ($Permission in $GraphPermissions) {
    $AppRole = $GraphAppRoles | Where-Object { $_.Value -eq $Permission }
    if ($AppRole) {
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ServicePrincipal.Id -AppRoleId $AppRole.Id -PrincipalId $ServicePrincipal.Id -ResourceId $GraphServicePrincipal.Id
        Write-Output "Assigned $Permission to the service principal."
    } else {
        Write-Output "Permission $Permission not found in Microsoft Graph app roles."
    }
}

# Generate a GUID for the secret
$SecretValue = [guid]::NewGuid().Guid

# Create the PasswordCredential object
$PasswordCredential = @{
    StartDateTime = (Get-Date).ToUniversalTime()
    EndDateTime = (Get-Date).AddYears(1).ToUniversalTime() # Set the expiration to 1 year from now
    SecretText = $SecretValue
    DisplayName = $ClientSecretDescription
}

# Add the Client Secret
$ClientSecret = New-AzADAppCredential -ObjectId $App.Id -PasswordCredentials @($PasswordCredential)

# Output the Client Secret Value
Write-Output "Client Secret created. Save this securely: $SecretValue"


# Output necessary details
Write-Output "Tenant ID: $TenantId"
Write-Output "Client ID: $ClientId"
Write-Output "Client Secret: $SecretValue"

