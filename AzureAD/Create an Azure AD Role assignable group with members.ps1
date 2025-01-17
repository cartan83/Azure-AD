<#
https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation?view=graph-powershell-1.0
This script uses a csv file that contains the details
   $groupName = $group.GroupName
    $role = $group.Role
    $users = $group.Users -split ";"
    $owners = $group.Owners -split ";"
    $description = $group.Description
#>
Install-Module Microsoft.Graph
Update-Module Microsoft.Graph
#Get-InstalledModule Microsoft.Graph
#Import-Module Microsoft.Graph

Import-Module Microsoft.Graph

# Ensure you are authenticated to Microsoft Graph
Connect-MgGraph -Scopes "Group.ReadWrite.All","Directory.ReadWrite.All","RoleManagement.ReadWrite.Directory"

# Path to the CSV file
$csvPath = ".\RH-AzureTenantAdmins.csv"

# Verify the CSV file exists
if (-not (Test-Path $csvPath)) {
    Write-Error "CSV file not found at path: $csvPath"
    return
}

# Import the CSV file
try {
    $groupsData = Import-Csv -Path $csvPath
} catch {
    Write-Error "Failed to import CSV file: $($_.Exception.Message)"
    return
}

# Initialize a log file and output CSV files
$logFile = ".\GroupCreationLog.txt"
if (Test-Path $logFile) { Remove-Item $logFile }
Start-Transcript -Path $logFile

$successOutput = @()
$failureOutput = @()

# Get tenant ID for tracking
$tenantId = (Get-MgOrganization).Id

foreach ($group in $groupsData) {
    # Parse data from CSV
    $groupName = $group.GroupName
    $role = $group.Role
    $users = $group.Users -split ";"
    $owners = $group.Owners -split ";"
    $description = $group.Description

    # Validate groupName and mailNickname
    $mailNickname = $groupName.Replace(" ", "")
    if ($mailNickname -match '[^a-zA-Z0-9_-]') {
        Write-Warning "Group name contains invalid characters: $groupName. Skipping group creation."
        $failureOutput += [PSCustomObject]@{
            TenantId     = $tenantId
            User         = ""
            GroupName    = $groupName
            Role         = $role
            ErrorMessage = "Invalid characters in group name."
        }
        continue
    }

    try {
        # Prepare the group creation parameters
        $ownersBinding = @(
            $owners | ForEach-Object {
                $ownerObject = Get-MgUser -Filter "mail eq '$_'"
                if ($ownerObject) {
                    "https://graph.microsoft.com/v1.0/users/$($ownerObject.Id)"
                } else {
                    Write-Warning "Owner not found: $_"
                }
            }
        )
        $membersBinding = @(
            $users | ForEach-Object {
                $memberObject = Get-MgUser -Filter "mail eq '$_'"
                if ($memberObject) {
                    "https://graph.microsoft.com/v1.0/users/$($memberObject.Id)"
                } else {
                    Write-Warning "User not found: $_"
                }
            }
        )
        
        # Updated parameters for security group assignable to roles
        $params = @{
            description       = $description
            displayName       = $groupName
            isAssignableToRole = $true
            mailEnabled       = $false
            securityEnabled   = $true
            mailNickname      = $mailNickname
            "owners@odata.bind" = $ownersBinding
            "members@odata.bind" = $membersBinding
        }

        # Create the role-assignable group
        Write-Host "Creating group: $groupName"
        $newGroup = New-MgGroup -BodyParameter $params
        $groupId = $newGroup.Id

        # Assign the role to the group
        Write-Host "Assigning role: $role to group: $groupName"
        $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$role'"
        if ($roleDefinition) {
            New-MgRoleManagementDirectoryRoleAssignment -PrincipalId $groupId -RoleDefinitionId $roleDefinition.Id -DirectoryScopeId "/"
        } else {
            Write-Warning "Role $role not found. Skipping role assignment."
            throw "Role not found."
        }

        # Log successful additions
        $successOutput += [PSCustomObject]@{
            TenantId  = $tenantId
            GroupName = $groupName
            Role      = $role
        }
    } catch {
        # Log the error
        $failureOutput += [PSCustomObject]@{
            TenantId     = $tenantId
            GroupName    = $groupName
            Role         = $role
            ErrorMessage = $_.Exception.Message
        }
    }
}

# Write the results to CSV files
$successFile = ".\SuccessResults.csv"
$failureFile = ".\FailureResults.csv"

$successOutput | Export-Csv -Path $successFile -NoTypeInformation -Force
$failureOutput | Export-Csv -Path $failureFile -NoTypeInformation -Force

Write-Host "Script completed. Results saved to $successFile and $failureFile."
Stop-Transcript
