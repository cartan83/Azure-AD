# Import the Microsoft.Graph module
Import-Module Microsoft.Graph

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.ReadWrite.All"

# Specify the user principal name (UPN) or user ID
$userId = "AZDeadPool@petsuppliesplus.com" # Replace with the actual user UPN or ID

# Generate a new secure password
$securePassword = [System.Web.Security.Membership]::GeneratePassword(16, 2)

# Update the user's password
Update-MgUser -UserId $userId -PasswordProfile @{Password = $securePassword; ForceChangePasswordNextSignIn = $false}

# Store the new password in an output variable
$outputPassword = $securePassword

# Output the new password for reference
Write-Output "New password for $userId: $outputPassword"

# Disconnect from Microsoft Graph
Disconnect-MgGraph

# Return the output variable
return $outputPassword


