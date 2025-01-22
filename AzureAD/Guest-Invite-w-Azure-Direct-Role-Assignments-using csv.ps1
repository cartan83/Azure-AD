# Import the Microsoft Graph Beta module
Install-Module Microsoft.Graph.Beta -Repository PSGallery -Force

# Authenticate with Microsoft Graph
$tenantId = "2e9b30c6-1ac4-4367-9b3a-25f08252ab01" # Provide the Tenant ID here
if (-not $tenantId) {
    Write-Host "Please specify a Tenant ID in the script." -ForegroundColor Red
    exit
}

Connect-MgGraph -TenantId $tenantId -Scopes "User.ReadWrite.All", "RoleManagement.ReadWrite.Directory", "Directory.AccessAsUser.All" -NoWelcome

# Verify authentication
if (-not (Get-MgContext)) {
    Write-Host "Failed to authenticate. Please check your credentials and try again." -ForegroundColor Red
    exit
}

# Path to the CSV file
$csvFilePath = ".\GuestUsers.csv"

# Valid ISO 3166-1 alpha-2 country codes
$validUsageLocations = @("US", "GB", "CA", "DE", "FR", "IN", "AU", "JP", "BR", "ZA") # Add more as needed$csv

# Step 1: Import CSV and process guest users
$guests = Import-Csv -Path $csvFilePath | ForEach-Object {
    $_.Roles = $_.Roles -replace "[^\x20-\x7E]", ""   # Remove non-printable ASCII characters
    $_.Roles = $_.Roles -replace "–", "-"            # Replace en-dash with a regular dash
    $_.Roles = $_.Roles -replace "\s{2,}", " "       # Replace multiple spaces with a single space
    $_
}

foreach ($guest in $guests) {
    Write-Host "Processing user: $($guest.Email)" -ForegroundColor Cyan

    try {
        # Validate UsageLocation
        if (-not $validUsageLocations -contains $guest.UsageLocation) {
            Write-Host "Invalid UsageLocation for $($guest.Email): $($guest.UsageLocation). Skipping." -ForegroundColor Red
            continue
        }

        # Check if the user already exists
        $existingUser = Get-MgUser -Filter "UserPrincipalName eq '$($guest.Email)' or Mail eq '$($guest.Email)'" -ErrorAction SilentlyContinue

        if ($existingUser) {
            Write-Host "User $($guest.Email) already exists. Skipping invitation." -ForegroundColor Green
        } else {
            # Send invitation to the guest user
            Write-Host "Sending invitation to: $($guest.Email)" -ForegroundColor Yellow
            $invitation = New-MgInvitation -InvitedUserEmailAddress $guest.Email `
                                            -InvitedUserDisplayName $guest.DisplayName `
                                            -SendInvitationMessage:$true `
                                            -InvitedUserMessageInfo @{
                                                CustomizedMessageBody = "Welcome $($guest.FirstName) to our tenant."
                                            } `
                                            -InvitedUserType "Guest" `
                                            -InviteRedirectUrl "https://myapps.microsoft.com"

            if ($invitation) {
                Write-Host "Invitation sent to: $($guest.Email)" -ForegroundColor Green
            } else {
                Write-Host "Failed to send invitation to: $($guest.Email)." -ForegroundColor Red
                continue
            }
        }

        # Get the invited user object
        $user = Get-MgUser -Filter "UserPrincipalName eq '$($guest.Email)'" -ErrorAction SilentlyContinue

        if ($user) {
            # Update user properties
            Update-MgUser -UserId $user.Id `
                          -GivenName $guest.FirstName `
                          -Surname $guest.LastName `
                          -JobTitle $guest.JobTitle `
                          -Department $guest.Department `
                          -CompanyName $guest.CompanyName `
                          -UsageLocation $guest.UsageLocation

            Write-Host "Updated properties for $($guest.Email)." -ForegroundColor Green

            # Assign roles to the user
            $roles = $guest.Roles -split "\|"
            foreach ($roleName in $roles) {
                Write-Host "Looking for role: $roleName" -ForegroundColor Cyan
                $role = Get-MgRoleDefinition -Filter "DisplayName eq '$roleName'" -ErrorAction SilentlyContinue

                if ($role) {
                    Write-Host "Assigning role '$roleName' to user: $($guest.Email)" -ForegroundColor Yellow
                    try {
                        New-MgRoleAssignment -PrincipalId $user.Id -RoleDefinitionId $role.Id -DirectoryScopeId "/"
                        Write-Host "Role '$roleName' assigned successfully to user: $($guest.Email)." -ForegroundColor Green
                    } catch {
                        Write-Host "Failed to assign role '$roleName' to user: $($guest.Email). Error: $_" -ForegroundColor Red
                    }
                } else {
                    Write-Host "Role '$roleName' not found. Skipping." -ForegroundColor Red
                }
            }
        } else {
            Write-Host "User not found after invitation. Skipping role assignment." -ForegroundColor Red
        }
    } catch {
        Write-Host "Error processing user $($guest.Email): $_" -ForegroundColor Red
    }
}

Write-Host "Processing completed!" -ForegroundColor Cyan
