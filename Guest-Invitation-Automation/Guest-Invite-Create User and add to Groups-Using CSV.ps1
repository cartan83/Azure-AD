
$tenantId = "972c0821-fe2d-4379-b6e8-acd0c3427548"
Connect-MgGraph -TenantId $tenantId -Scopes "User.ReadWrite.All", "RoleManagement.ReadWrite.Directory", "Directory.AccessAsUser.All", "Directory.ReadWrite.All"

# Log file setup
$tenantId = (Get-MgOrganization).Id
$logFile = "GuestsCreated-$tenantId.txt"
Start-Transcript -Path $logFile -Append

# Verify authentication
if (-not (Get-MgContext)) {
    Write-Host "Failed to authenticate. Please check your credentials and try again." -ForegroundColor Red
    Stop-Transcript
    exit
}

Get-MgContext

# Path to the CSV file
$csvFilePath = ".\D365 Developer-Sunrise.csv"

# Valid ISO 3166-1 alpha-2 country codes
$validUsageLocations = @("US", "GB", "CA", "DE", "FR", "IN", "AU", "JP", "BR", "ZA")

# Import CSV and process guest users
$guests = Import-Csv -Path $csvFilePath | ForEach-Object {
    $_.Groups = $_.Groups -split "\|"  # Split groups into an array
    $_
}

foreach ($guest in $guests) {
    Write-Host "Processing user: $($guest.Mail)" -ForegroundColor Cyan
    Write-Output "Processing user: $($guest.Mail)"

    try {
        # Validate UsageLocation
        if (-not $validUsageLocations -contains $guest.UsageLocation) {
            $msg = "Invalid UsageLocation for $($guest.Mail): $($guest.UsageLocation). Skipping."
            Write-Host $msg -ForegroundColor Red
            Write-Output $msg
            continue
        }

        # Check if the user already exists
        $existingUser = Get-MgUser -Filter "UserPrincipalName eq '$($guest.UPN)' or Mail eq '$($guest.Mail)'" -ErrorAction SilentlyContinue

        if ($existingUser) {
            $msg = "User $($guest.Mail) already exists. Skipping invitation."
            Write-Host $msg -ForegroundColor Green
            Write-Output $msg
            $user = $existingUser
        } else {
            # Send invitation to the guest user
            Write-Host "Sending invitation to: $($guest.Email)" -ForegroundColor Yellow
            Write-Output "Sending invitation to: $($guest.Email)"

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
                Write-Output $msg

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
                        Write-Output $msg
                    } else {
                        $msg = "User not found for the invitation ID: $($invitation.Id)"
                        Write-Host $msg -ForegroundColor Red
                        Write-Output $msg
                    }
                } catch {
                    $msg = "Error updating user properties for invitation ID: $($invitation.Id). Error: $_"
                    Write-Host $msg -ForegroundColor Red
                    Write-Output $msg
                }
            } else {
                $msg = "No invitation object was created. Skipping user processing."
                Write-Host $msg -ForegroundColor Yellow
                Write-Output $msg
            }
        }

        # Assign user to Entra ID groups
        foreach ($groupName in $guest.Groups -split ";") {
            $group = Get-MgGroup -Filter "DisplayName eq '$groupName'" -ErrorAction SilentlyContinue

            if ($group) {
                Write-Host "Adding user to group: '$groupName'" -ForegroundColor Yellow
                Write-Output "Adding user to group: '$groupName'"

                try {
                    New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id

                    $msg = "User $($guest.Mail) successfully added to group '$groupName'."
                    Write-Host $msg -ForegroundColor Green
                    Write-Output $msg
                } catch {
                    $msg = "Failed to add user $($guest.Mail) to group '$groupName'. Error: $_"
                    Write-Host $msg -ForegroundColor Red
                    Write-Output $msg
                }
            } else {
                $msg = "Group '$groupName' not found. Skipping."
                Write-Host $msg -ForegroundColor Red
                Write-Output $msg
            }
        }
    } catch {
        $msg = "Error processing user $($guest.Mail): $_"
        Write-Host $msg -ForegroundColor Red
        Write-Output $msg
    }
}

Write-Host "Processing completed!" -ForegroundColor Cyan
Write-Output "Processing completed!"
Stop-Transcript
