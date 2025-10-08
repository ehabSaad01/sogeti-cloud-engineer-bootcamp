# Day02 Governance - Azure PowerShell
# Goal: Enforce governance with Resource Group + Policy + RBAC. Secure-by-default. Comments in English.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- 0) Context --------------------------------------------------------------
# Ensure Az modules are installed and you are logged in: Connect-AzAccount
$subId = (Get-AzContext).Subscription.Id
$userObjId = (Get-AzADUser -SignedIn).Id

# --- 1) Create Resource Group -----------------------------------------------
# Creates the training resource group in West Europe with tracking tags.
New-AzResourceGroup -Name "rg-day02-governance-ps" -Location "westeurope" -Tag @{
    env  = "training"
    owner= "ehab"
    day  = "02"
} | Out-Null

# --- 2) Assign Policy: Allowed locations at Subscription scope ---------------
# Built-in "Allowed locations" definition GUID.
$allowedLocationsDefId = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
$allowedLocationsParams = @{
    "listOfAllowedLocations" = @{ "value" = @("westeurope") }
}
New-AzPolicyAssignment -Name "allowed-locations-ps" `
    -DisplayName "Allowed locations - West Europe only" `
    -Scope "/subscriptions/$subId" `
    -PolicyDefinitionId $allowedLocationsDefId `
    -PolicyParameterObject $allowedLocationsParams | Out-Null

# --- 3) Assign Policy: Require a tag and its value at RG scope ---------------
# Built-in "Require a tag and its value on resources" definition GUID.
$requireTagDefId = "/providers/Microsoft.Authorization/policyDefinitions/1e30110a-5ceb-460c-a204-c1c3969c6d62"
$requireTagParams = @{
    "tagName"  = @{ "value" = "owner" }
    "tagValue" = @{ "value" = "ehab" }
}
New-AzPolicyAssignment -Name "require-owner-tag-ps" `
    -DisplayName "Require tag owner=ehab on resources" `
    -Scope "/subscriptions/$subId/resourceGroups/rg-day02-governance-ps" `
    -PolicyDefinitionId $requireTagDefId `
    -PolicyParameterObject $requireTagParams | Out-Null

# --- 4) RBAC: Assign Contributor on RG to the signed-in user -----------------
New-AzRoleAssignment -ObjectId $userObjId `
    -RoleDefinitionName "Contributor" `
    -Scope "/subscriptions/$subId/resourceGroups/rg-day02-governance-ps" | Out-Null

Write-Output "Day02 governance via PowerShell: completed."
