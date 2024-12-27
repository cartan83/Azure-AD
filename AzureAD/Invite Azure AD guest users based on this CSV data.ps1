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
#>

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
                                            customizedMessageBody = "Hello $($guest.FirstName), you've been invited as a guest to adminster this tenant."
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
        }
        
        Write-Host "Invitation sent to: $($guest.Email)"
    }
}
