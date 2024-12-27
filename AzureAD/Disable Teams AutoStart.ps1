# Name: Detect-DisableAutostartBothTeams
# Purpose: Detect if Classic and NEW Teams is set to Auto start

# Detection if Classic Teams Autostart is enabled
$regKeyPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$regValueName = "com.squirrel.Teams.Teams"

$valueExists = (Get-Item $regKeyPath -EA Ignore).Property -contains $regValueName

if (!$valueExists) {
    Write-Output "Classic Teams Autostart is disabled or not available at all"
} else {
    Write-Output "Classic Teams Autostart is enabled - exiting with code 1"
    exit 1
}

# Detection if NEW Teams Autostart is enabled
$rpath = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask"

try {
    $v = Get-ItemPropertyValue -Path $rpath -Name "State" -ErrorAction Stop

    if ($v -eq "0") {
        Write-Output "Autostart NEW Teams is already Disabled"
        exit 0
    } else {
        Write-Output "Autostart NEW Teams is still Enabled"
        exit 1
    }
} catch {
    Write-Output "Error: $_"
    Write-Output "NEW Teams is probably not installed and does not need to be disabled"
    exit 0
}