#Authenticate to Azure Using an App Registration
$tenantId = "972c0821-fe2d-4379-b6e8-acd0c3427548"
$clientId = "eed72adc-78db-450b-8f08-a5b883d1e86f"
$clientSecret = "ixxxxxxxxxxxxxxxxxxxxxxxxxxxx"
 
# Get an access token
$body = @{
    grant_type    = "client_credentials"
    scope         = "https://graph.microsoft.com/.default"
    client_id     = $clientId
    client_secret = $clientSecret
}
 
$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -ContentType "application/x-www-form-urlencoded" -Body $body
$accessToken = $tokenResponse.access_token
$headers = @{ Authorization = "Bearer $accessToken" }

Write-Host $accessToken

# Fetch ALL devices (handle pagination)
$uri = "https://graph.microsoft.com/beta/devices"
$allDevices = @()

do {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    $allDevices += $response.value
    $uri = $response."@odata.nextLink"  # Get next page if exists
} while ($uri)

# Show all devices found
Write-Host "`n🔹 List of Available Devices (Total: $($allDevices.Count))" -ForegroundColor Cyan
$allDevices | Select-Object displayName, id, operatingSystem | Format-Table -AutoSize

# Prompt user for the Device Display Name
$deviceName = Read-Host "`nEnter the exact Device Display Name"

# Search for the device (case-insensitive, allowing partial matches)
$matchingDevices = $allDevices | Where-Object { $_.displayName -match "$deviceName" }

if ($matchingDevices) {
    foreach ($device in $matchingDevices) {
        # Display device details
        Write-Host "`n✅ Device Found!" -ForegroundColor Green
        Write-Host "---------------------------------------"
        Write-Host "Device ID   : $($device.id)"
        Write-Host "Display Name: $($device.displayName)"
        Write-Host "OS          : $($device.operatingSystem)"
        Write-Host "OS Version  : $($device.operatingSystemVersion)"
        Write-Host "Join Type   : $($device.deviceTrustType)"
        Write-Host "Compliance  : $($device.complianceExpirationDateTime)"
        Write-Host "Management  : $($device.managementType)"
        Write-Host "Registered  : $($device.approximateLastSignInDateTime)"
        Write-Host "---------------------------------------`n"
    }
} else {
    Write-Host "❌ No device found with the name '$deviceName'. Try checking case, spaces, or partial searches." -ForegroundColor Red
}



