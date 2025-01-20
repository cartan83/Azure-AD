<#
invite Azure AD guest users based on this CSV data:
Email (the guest's email address)
Display name (the user's display name)
First name
Last name
Job title
Company name
Department
User type (set to "Guest")
Usage location
Check if the user already exists: The Get-MgUser cmdlet filters users based on their UserPrincipalName or Mail. If a match is found, the script skips sending an invitation.
Skip existing users: If a user is already present in the tenant, a message will be displayed, and no invitation will be sent for that user.
_____________________________________________________________________________________________________________________
CSV Format-
Email,UPN,FirstName,LastName,DisplayName,JobTitle,CompanyName,Department,Manager,UsageLocation,Groups
user1@example.com,user1@example.com,John,Doe,John Doe,IT Specialist,TechCorp,IT Department,manager@example.com,US,Group1|Group2|Group3
user2@example.com,user2@example.com,Jane,Smith,Jane Smith,HR Manager,TechCorp,HR Department,manager2@example.com,US,Group2|Group4
#>
Import-Module Microsoft.Graph.Beta

# Authenticate with Microsoft Graph
Connect-MgGraph -Scopes "User.ReadWrite.All", "GroupMember.ReadWrite.All", "Directory.AccessAsUser.All"

# Verify authentication
if (-not (Get-MgContext)) {
    Write-Host "Failed to authenticate. Please check your credentials and try again."
    exit
}

# Path to your CSV file
$csvFilePath = ".\GuestUsers.csv"

# Valid ISO 3166-1 alpha-2 country codes
$validUsageLocations = @("US", "GB", "CA", "DE", "FR", "IN", "AU", "JP", "BR", "ZA") # Add more as needed

# Import and sanitize CSV data
$guests = Import-Csv -Path $csvFilePath | ForEach-Object {
    Write-Host "Processing guest: $($_.Email)"
    $_.Groups = $_.Groups -replace "[^\x20-\x7E]", ""   # Remove non-printable ASCII characters
    $_.Groups = $_.Groups -replace "–", "-"            # Replace en-dash with a regular dash
    $_.Groups = $_.Groups -replace "\s{2,}", " "       # Replace multiple spaces with a single space
    $_
}

# Debugging: Output sanitized $guests to verify correctness
Write-Host "Sanitized guest data:" -ForegroundColor Yellow
$guests | Format-Table -AutoSize

# Loop through each user in the CSV
foreach ($guest in $guests) {
    Write-Host "Starting processing for: $($guest.Email)" -ForegroundColor Cyan
    try {
        # Validate UsageLocation
        if (-not $validUsageLocations -contains $guest.UsageLocation) {
            Write-Host "Invalid UsageLocation for $($guest.Email): $($guest.UsageLocation). Skipping." -ForegroundColor Red
            continue
        }

        # Check if the user already exists in Azure AD
        $existingUser = Get-MgUser -Filter "UserPrincipalName eq '$($guest.Email)' or Mail eq '$($guest.Email)'" -ErrorAction SilentlyContinue

        if ($existingUser) {
            Write-Host "User $($guest.Email) already exists in the tenant. Updating properties..." -ForegroundColor Green
            # Update existing user properties
            Update-MgUser -UserId $existingUser.Id `
                          -GivenName $guest.FirstName `
                          -Surname $guest.LastName `
                          -JobTitle $guest.JobTitle `
                          -Department $guest.Department `
                          -CompanyName $guest.CompanyName `
                          -UsageLocation $guest.UsageLocation

            # Update manager
            if ($guest.Manager) {
                try {
                    $managerId = (Get-MgUser -Filter "UserPrincipalName eq '$($guest.Manager)'" | Select-Object -ExpandProperty Id)
                    if ($managerId) {
                        $bodyParameter = @{
                            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$managerId"
                        }
                        Set-MgUserManagerByRef -UserId $existingUser.Id -BodyParameter $bodyParameter
                        Write-Host "Manager updated for $($guest.Email)" -ForegroundColor Green
                    } else {
                        Write-Host "Manager $($guest.Manager) not found. Skipping." -ForegroundColor Red
                    }
                } catch {
                    Write-Host "Error updating manager for $($guest.Email): $_" -ForegroundColor Red
                }
            }

            # Add to groups
            if ($guest.Groups) {
                $groups = $guest.Groups -split "\|"
                foreach ($groupName in $groups) {
                    try {
                        # Normalize and debug group name
                        $groupName = $groupName.Trim() -replace "–", "-" -replace "\s{2,}", " "
                        Write-Host "Looking for group: $groupName" -ForegroundColor Cyan

                        # Find the group
                        $group = Get-MgGroup -Filter "DisplayName eq '$groupName'" -ErrorAction SilentlyContinue
                        if ($group) {
                            # Construct the OdataId for the user
                            $odataId = "https://graph.microsoft.com/v1.0/directoryObjects/$($existingUser.Id)"
                            
                            # Add the user to the group using New-MgGroupMemberByRef
                            New-MgGroupMemberByRef -GroupId $group.Id -OdataId $odataId
                            Write-Host "Added $($guest.Email) to group $groupName" -ForegroundColor Green
                        } else {
                            Write-Host "Group $groupName not found. Skipping." -ForegroundColor Red
                        }
                    } catch {
                        Write-Host "Error adding $($guest.Email) to group $groupName $_" -ForegroundColor Red
                    }
                }
            }
        } else {
            # User not found; send invitation
            Write-Host "User $($guest.Email) not found. Sending invitation..." -ForegroundColor Cyan
            $invitation = New-MgInvitation -InvitedUserEmailAddress $guest.Email `
                                            -InvitedUserDisplayName $guest.DisplayName `
                                            -SendInvitationMessage:$true `
                                            -InvitedUserMessageInfo @{
                                                CustomizedMessageBody = "Hello $($guest.FirstName), you've been invited to our tenant."
                                            } `
                                            -InvitedUserType "Guest" `
                                            -InviteRedirectUrl "https://myapps.microsoft.com"

            if ($invitation) {
                Write-Host "Invitation sent to: $($guest.Email)" -ForegroundColor Green

                # Update user properties after invitation is created
                $invitedUser = Get-MgUser -UserId $invitation.InvitedUser.Id
                Update-MgUser -UserId $invitedUser.Id `
                              -GivenName $guest.FirstName `
                              -Surname $guest.LastName `
                              -JobTitle $guest.JobTitle `
                              -Department $guest.Department `
                              -CompanyName $guest.CompanyName `
                              -UsageLocation $guest.UsageLocation

                # Update manager
                if ($guest.Manager) {
                    try {
                        $managerId = (Get-MgUser -Filter "UserPrincipalName eq '$($guest.Manager)'" | Select-Object -ExpandProperty Id)
                        if ($managerId) {
                            $bodyParameter = @{
                                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$managerId"
                            }
                            Set-MgUserManagerByRef -UserId $invitedUser.Id -BodyParameter $bodyParameter
                            Write-Host "Manager updated for $($guest.Email)" -ForegroundColor Green
                        } else {
                            Write-Host "Manager $($guest.Manager) not found. Skipping." -ForegroundColor Red
                        }
                    } catch {
                        Write-Host "Error updating manager for $($guest.Email): $_" -ForegroundColor Red
                    }
                }

                # Add to groups
                if ($guest.Groups) {
                    $groups = $guest.Groups -split "\|"
                    foreach ($groupName in $groups) {
                        try {
                            # Normalize and debug group name
                            $groupName = $groupName.Trim() -replace "–", "-" -replace "\s{2,}", " "
                            Write-Host "Looking for group: $groupName" -ForegroundColor Cyan

                            # Find the group
                            $group = Get-MgGroup -Filter "DisplayName eq '$groupName'" -ErrorAction SilentlyContinue
                            if ($group) {
                                # Construct the OdataId for the user
                                $odataId = "https://graph.microsoft.com/v1.0/directoryObjects/$($invitedUser.Id)"
                                
                                # Add the user to the group using New-MgGroupMemberByRef
                                New-MgGroupMemberByRef -GroupId $group.Id -OdataId $odataId
                                Write-Host "Added $($guest.Email) to group $groupName" -ForegroundColor Green
                            } else {
                                Write-Host "Group $groupName not found. Skipping." -ForegroundColor Red
                            }
                        } catch {
                            Write-Host "Error adding $($guest.Email) to group $groupName $_" -ForegroundColor Red
                        }
                    }
                }
            } else {
                Write-Host "Failed to send invitation to $($guest.Email)." -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "Error processing user $($guest.Email): $_" -ForegroundColor Red
    }
}







