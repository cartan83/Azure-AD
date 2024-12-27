<#
Steps:
1. Run this script to create the Entrprise app on the tenant
2. Go to the Tenant and rcreate the custom role CloudAbilityDataReader using the json file
#>

$cldyServicePrincipalAppId = "1ba79ced-1862-41d1-95bc-66d6bc5aff7f"
$cldyServicePrincipalObjectId = (Get-AzADServicePrincipal -ApplicationId $cldyServicePrincipalAppId).id
if (!$cldyServicePrincipalObjectId) {
  New-AzADServicePrincipal -ApplicationId $cldyServicePrincipalAppId
  $cldyServicePrincipalObjectId = (Get-AzADServicePrincipal -ApplicationId $cldyServicePrincipalAppId).id
} else {
  echo "Service principal already present, skipping new service principal creation"
}