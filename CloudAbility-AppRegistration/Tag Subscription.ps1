<#
This script adds tag cost-center to all subscription listed in a csv that contains the tag value.
example of csv content:
Subscription GUID	                 Cost Center
4b03d98a-bfb5-4c3a-abd7-14f4e25d4a69	109
933d9573-efeb-4b58-8853-7e361cf807b6	109
5dd854a6-6490-40bc-9674-19eeeb287de5	126
395a1575-14e2-4a48-91d8-2049b89d778c	126
d0050fd8-4253-465a-bbbc-83fab9da5e49	126
_______________________________________________________________________________________________
#>
# Define variables
$tenantId = "64dc69e4-d083-49fc-9569-ebece1dd1408"
$csvFilePath = "Prod-rh-Subtags.csv"
#$credential = Get-Credential

# Connect to Azure
#Connect-AzAccount -Credential $credential -Tenant $tenantId

# Read CSV file
$subscriptions = Import-Csv $csvFilePath

# Iterate through each row in the CSV file
foreach ($subscriptionRow in $subscriptions) {
    $subscriptionId = $subscriptionRow.'Subscription GUID'
    $costCenter = $subscriptionRow.'Cost Center'

    # Check if subscription exists
    $existingSubscription = Get-AzSubscription -SubscriptionId $subscriptionId -ErrorAction SilentlyContinue

    if ($existingSubscription) {
        # Add tags to subscription
        $tags = @{
            "cost-center" = $costCenter
        }
        $subscriptionResourceId = "/subscriptions/$subscriptionId"
        New-AzTag -ResourceId $subscriptionResourceId -Tag $tags

        Write-Host "Tag 'cost-center' with value '$costCenter' has been applied to subscription '$($existingSubscription.Name)'."
    } else {
        Write-Warning "Subscription with ID '$subscriptionId' does not exist in the specified Azure tenant."
    }
}