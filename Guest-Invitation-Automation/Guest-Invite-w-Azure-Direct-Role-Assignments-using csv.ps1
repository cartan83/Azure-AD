# Import the Microsoft Graph Beta module
Install-Module Microsoft.Graph.Beta -Repository PSGallery -Force
$graphBetaInstalled = Get-InstalledModule Microsoft.Graph.beta
Write-Host "Graph Beta Module Installed: $graphBetaInstalled"

Install-Module Microsoft.Graph -Repository PSGallery -Force
$graphInstalled = Get-InstalledModule Microsoft.Graph
Write-Host "Graph Module Installed: $graphInstalled"

<##
# Prompt for Tenant ID
$tenantId = Read-Host "Enter the Tenant ID"
if (-not $tenantId) {
    Write-Host "Tenant ID is required." -ForegroundColor Red
    exit
}
#>

<#
# Prompt for user credentials
$cred = Get-Credential -Message "Enter your Azure credentials"
Connect-MgGraph -TenantId $tenantId -Scopes "User.ReadWrite.All", "RoleManagement.ReadWrite.Directory", "Directory.AccessAsUser.All", "Directory.ReadWrite.All" -Credential $cred
#>
$Context = Get-AzContext
Write-Output $Context

# Log file setup
$logFile = "ITCP-GuestAdmins-$tenantId.txt"
Start-Transcript -Path $logFile -Append

# Verify authentication
if (-not (Get-MgContext)) {
    Write-Host "Failed to authenticate. Please check your credentials and try again." -ForegroundColor Red
    Stop-Transcript
    exit
}

# Path to the CSV file
$csvFilePath = ".\GuestUsers.csv"

# Valid ISO 3166-1 alpha-2 country codes
$validUsageLocations = @("US", "GB", "CA", "DE", "FR", "IN", "AU", "JP", "BR", "ZA") # Add more as needed

# Import CSV and process guest users
$guests = Import-Csv -Path $csvFilePath | ForEach-Object {
    $_.Roles = $_.Roles -replace "[^\x20-\x7E]", ""   # Remove non-printable ASCII characters
    $_.Roles = $_.Roles -replace "–", "-"            # Replace en-dash with a regular dash
    $_.Roles = $_.Roles -replace "\s{2,}", " "       # Replace multiple spaces with a single space
    $_
}

foreach ($guest in $guests) {
    Write-Host "Processing user: $($guest.Mail)" -ForegroundColor Cyan
    Add-Content -Path $logFile -Value "Processing user: $($guest.Mail)"

    try {
        # Validate UsageLocation
        if (-not $validUsageLocations -contains $guest.UsageLocation) {
            $msg = "Invalid UsageLocation for $($guest.Mail): $($guest.UsageLocation). Skipping."
            Write-Host $msg -ForegroundColor Red
            Add-Content -Path $logFile -Value $msg
            continue
        }

        # Check if the user already exists
        $existingUser = Get-MgUser -Filter "UserPrincipalName eq '$($guest.UPN)' or Mail eq '$($guest.Mail)'" -ErrorAction SilentlyContinue

        if ($existingUser) {
            $msg = "User $($guest.Mail) already exists. Skipping invitation."
            Write-Host $msg -ForegroundColor Green
            Add-Content -Path $logFile -Value $msg
            $user = $existingUser
        } else {
            # Send invitation to the guest user
            Write-Host "Sending invitation to: $($guest.Email)" -ForegroundColor Yellow
            Add-Content -Path $logFile -Value "Sending invitation to: $($guest.Email)"

            $invitation = New-MgInvitation -InvitedUserEmailAddress $guest.Email `
                                            -InvitedUserDisplayName $guest.DisplayName `
                                            -SendInvitationMessage:$true `
                                            -InvitedUserMessageInfo @{
                                                CustomizedMessageBody = "Welcome $($guest.FirstName) to our tenant."
                                            } `
                                            -InvitedUserType "Guest" `
                                            -InviteRedirectUrl "https://myapps.microsoft.com"

            if ($invitation) {
                $msg = "Invitation sent. Redeem URL: $($invitation.InviteRedeemUrl)"
                Write-Host $msg -ForegroundColor Green
                Add-Content -Path $logFile -Value $msg

                try {
                    # Retrieve the invited user using the ID from the invitation
                    $user = Get-MgUser -UserId $invitation.InvitedUser.Id

                    if ($user) {
                        # Update user properties
                        Update-MgUser -UserId $user.Id `
                                      -GivenName $guest.FirstName `
                                      -Surname $guest.LastName `
                                      -JobTitle $guest.JobTitle `
                                      -Department $guest.Department `
                                      -CompanyName $guest.CompanyName `
                                      -UsageLocation $guest.UsageLocation

                        $msg = "User properties updated successfully for: $($user.UserPrincipalName)"
                        Write-Host $msg -ForegroundColor Green
                        Add-Content -Path $logFile -Value $msg
                    } else {
                        $msg = "User not found for the invitation ID: $($invitation.Id)"
                        Write-Host $msg -ForegroundColor Red
                        Add-Content -Path $logFile -Value $msg
                    }
                } catch {
                    $msg = "Error updating user properties for invitation ID: $($invitation.Id). Error: $_"
                    Write-Host $msg -ForegroundColor Red
                    Add-Content -Path $logFile -Value $msg
                }
            } else {
                $msg = "No invitation object was created. Skipping user processing."
                Write-Host $msg -ForegroundColor Yellow
                Add-Content -Path $logFile -Value $msg
            }
        }

        # Assign roles to the user
        foreach ($roleName in $guest.Roles -split ";") {
            $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$roleName'" -ErrorAction SilentlyContinue

            if ($roleDefinition) {
                Write-Host "Assigning role '$roleName' to user: $($guest.Email)" -ForegroundColor Yellow
                Add-Content -Path $logFile -Value "Assigning role '$roleName' to user: $($guest.Email)"

                try {
                    $directoryScope = "/" # Global scope
                    $params = @{
                        "@odata.type" = "#microsoft.graph.unifiedRoleAssignment"
                        roleDefinitionId = $roleDefinition.Id
                        principalId = $user.Id
                        directoryScopeId = $directoryScope
                    }

                    New-MgRoleManagementDirectoryRoleAssignment -BodyParameter $params

                    $msg = "Role '$roleName' assigned successfully to user: $($guest.Email)."
                    Write-Host $msg -ForegroundColor Green
                    Add-Content -Path $logFile -Value $msg
                } catch {
                    $msg = "Failed to assign role '$roleName' to user: $($guest.Email). Error: $_"
                    Write-Host $msg -ForegroundColor Red
                    Add-Content -Path $logFile -Value $msg
                }
            } else {
                $msg = "Role '$roleName' not found. Skipping."
                Write-Host $msg -ForegroundColor Red
                Add-Content -Path $logFile -Value $msg
            }
        }
    } catch {
        $msg = "Error processing user $($guest.Email): $_"
        Write-Host $msg -ForegroundColor Red
        Add-Content -Path $logFile -Value $msg
    }
}

Write-Host "Processing completed!" -ForegroundColor Cyan
Add-Content -Path $logFile -Value "Processing completed!"
Stop-Transcript
