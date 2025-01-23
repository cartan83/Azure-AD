# Import the Microsoft Graph Beta module
Import-Module Microsoft.Graph.Beta

# Authenticate with Microsoft Graph
$tenantId = "2e9b30c6-1ac4-4367-9b3a-25f08252ab01" # Provide the Tenant ID here
if (-not $tenantId) {
    Write-Host "Please specify a Tenant ID in the script." -ForegroundColor Red
    exit
}

Connect-MgGraph -TenantId $tenantId -Scopes "User.ReadWrite.All", "GroupMember.ReadWrite.All", "RoleManagement.ReadWrite.Directory", "Directory.AccessAsUser.All"

# Verify authentication
if (-not (Get-MgContext)) {
    Write-Host "Failed to authenticate. Please check your credentials and try again." -ForegroundColor Red
    exit
}

# Path to the CSV file
$csvFilePath = ".\GuestUsers.csv"

# Role-Assignable Group Name
$roleAssignableGroupName = "RH-ITPC-Global Administrator"

# Valid ISO 3166-1 alpha-2 country codes
$validUsageLocations = @("US", "GB", "CA", "DE", "FR", "IN", "AU", "JP", "BR", "ZA") # Add more as needed

# Step 1: Check or Create the Role-Assignable Group
Write-Host "Checking if role-assignable group exists..." -ForegroundColor Cyan
$group = Get-MgGroup -Filter "DisplayName eq '$roleAssignableGroupName'" -ErrorAction SilentlyContinue

if ($group) {
    if ($group.IsAssignableToRole) {
        Write-Host "Role-assignable group '$roleAssignableGroupName' already exists in tenant: $($group.Id)." -ForegroundColor Green
        $skipGroupActions = $true
    } else {
        Write-Host "A group with the name '$roleAssignableGroupName' already exists but is not role-assignable. Exiting script." -ForegroundColor Red
        exit
    }
} else {
    Write-Host "Group '$roleAssignableGroupName' does not exist. Creating group." -ForegroundColor Yellow
    $group = New-MgGroup -DisplayName $roleAssignableGroupName `
                         -MailEnabled:$false `
                         -MailNickname ($roleAssignableGroupName -replace " ", "") `
                         -SecurityEnabled:$true `
                         -IsAssignableToRole:$true
    Write-Host "Group created successfully." -ForegroundColor Green
    $skipGroupActions = $false
}

# Step 2: Assign Roles to the Role-Assignable Group
if (-not $skipGroupActions) {
    $rolesAssigned = $false
    $csvRoles = (Import-Csv -Path $csvFilePath | Select-Object -ExpandProperty Roles | Sort-Object -Unique)
    foreach ($roleName in $csvRoles) {
        Write-Host "Looking for role: $roleName" -ForegroundColor Cyan
        $role = Get-MgRoleDefinition -Filter "DisplayName eq '$roleName'" -ErrorAction SilentlyContinue

        if ($role) {
            Write-Host "Assigning role '$roleName' to group: $($group.DisplayName)" -ForegroundColor Yellow
            try {
                New-MgRoleAssignment -PrincipalId $group.Id -RoleDefinitionId $role.Id -DirectoryScopeId "/"
                Write-Host "Role '$roleName' assigned successfully." -ForegroundColor Green
                $rolesAssigned = $true
            } catch {
                Write-Host "Failed to assign role '$roleName' to group. Error: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "Role '$roleName' not found. Skipping." -ForegroundColor Red
        }
    }

    if (-not $rolesAssigned) {
        Write-Host "No roles were successfully assigned to the group." -ForegroundColor Red
    } else {
        Write-Host "Roles assigned successfully." -ForegroundColor Green
    }
} else {
    Write-Host "Skipping role assignment and member addition as the group already exists." -ForegroundColor Yellow
}

# Step 3: Import CSV and process guest users
$guests = Import-Csv -Path $csvFilePath | ForEach-Object {
    $_.Group = $_.Group -replace "[^\x20-\x7E]", ""   # Remove non-printable ASCII characters
    $_.Group = $_.Group -replace "–", "-"            # Replace en-dash with a regular dash
    $_.Group = $_.Group -replace "\s{2,}", " "       # Replace multiple spaces with a single space
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

            if (-not $skipGroupActions) {
                # Add user to the Role-Assignable Group
                $odataId = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
                New-MgGroupMemberByRef -GroupId $group.Id -OdataId $odataId
                Write-Host "Added $($guest.Email) to group: $($roleAssignableGroupName)" -ForegroundColor Green
            }
        } else {
            Write-Host "User not found after invitation. Skipping group assignment." -ForegroundColor Red
        }
    } catch {
        Write-Host "Error processing user $($guest.Email): $_" -ForegroundColor Red
    }
}

Write-Host "Processing completed!" -ForegroundColor Cyan
