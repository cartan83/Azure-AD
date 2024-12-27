# Import necessary modules
Import-Module Microsoft.Graph.Beta

# Set tenant context if required
# Connect-MgGraph -TenantId "<your-tenant-id>"

# Path to your CSV file
$csvFilePath = "C:\Temp\ITPC-Admins.csv"

# Import CSV data
$guests = Import-Csv -Path $csvFilePath

# Loop through each user in the CSV and check if they are already in the tenant
foreach ($guest in $guests) {
    # Check if the user already exists in Azure AD
    $existingUser = Get-MgUser -Filter "UserPrincipalName eq '$($guest.Email)' or Mail eq '$($guest.Email)'" -ErrorAction SilentlyContinue

    if ($existingUser) {
        Write-Host "User $($guest.Email) already exists in the tenant. Skipping invitation."
    } else {
        # If the user does not exist, send the invitation
        $invitation = New-MgInvitation -InvitedUserEmailAddress $guest.Email `
                                        -InvitedUserDisplayName $guest."Display name" `
                                        -SendInvitationMessage $true `
                                        -InvitedUserMessageInfo @{
                                            customizedMessageBody = "Hello $($guest.FirstName), you've been invited as a guest to administer this tenant."
                                        } `
                                        -InvitedUserType $guest."User type" `
                                        -InviteRedirectUrl "https://myapps.microsoft.com"

        # Set additional properties for the guest user after they accept the invitation
        if ($invitation.Status -eq "Completed") {
            $user = Get-MgUser -UserId $invitation.InvitedUser.Id

            # Update user properties
            Update-MgUser -UserId $user.Id -JobTitle $guest."Job title" `
                          -Department $guest.Department `
                          -CompanyName $guest."Company name" `
                          -UsageLocation $guest."Usage location"

            # Get the role based on the CSV data in the "Azure AD Role Assignment" column
            $roleName = $guest."Azure AD Role Asignment"

            # Get the role object ID for the specified role
            $role = Get-MgDirectoryRole -Filter "displayName eq '$roleName'" | Select-Object -First 1

            if ($role) {
                try {
                    # Assign the role to the user
                    Add-MgDirectoryRoleMember -DirectoryRoleId $role.Id -UserId $user.Id
                    Write-Host "Assigned '$roleName' role to $($guest.Email)"
                } catch {
                    Write-Host "Failed to assign '$roleName' role to $($guest.Email): $_"
                }
            } else {
                Write-Host "Role '$roleName' not found for $($guest.Email)."
            }
        }

        Write-Host "Invitation sent to: $($guest.Email)"
    }
}
