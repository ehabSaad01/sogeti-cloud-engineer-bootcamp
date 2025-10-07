# Day01 — Foundation (Secure Monitoring Baseline) - PowerShell
# Requires Az modules. Run in Azure Cloud Shell (PowerShell).
# Style: long parameter names, clear comments, no loops, secure-by-default.

# --- Settings ----------------------------------------------------------------
$Location = "westeurope"
$ResourceGroup = "rg-day01-foundation"
$WorkspaceName = "law01weu"
$StorageName = "stlog01weu"

# --- Resource Group ----------------------------------------------------------
if (-not (Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $ResourceGroup -Location $Location -Tag @{ env="lab"; owner="ehab" } | Out-Null
}

# --- Log Analytics Workspace -------------------------------------------------
$law = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -Name $WorkspaceName -ErrorAction SilentlyContinue
if (-not $law) {
    New-AzOperationalInsightsWorkspace `
        -ResourceGroupName $ResourceGroup `
        -Name $WorkspaceName `
        -Location $Location `
        -Sku "PerGB2018" `
        -Tag @{ env="lab"; owner="ehab" } | Out-Null
    $law = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -Name $WorkspaceName
}
$WorkspaceResourceId = $law.ResourceId
$WorkspaceCustomerId = $law.CustomerId

# --- Storage Account (secure posture) ---------------------------------------
$st = Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageName -ErrorAction SilentlyContinue
if (-not $st) {
    New-AzStorageAccount `
        -ResourceGroupName $ResourceGroup `
        -Name $StorageName `
        -Location $Location `
        -SkuName "Standard_GRS" `
        -Kind "StorageV2" `
        -EnableHttpsTrafficOnly $true `
        -AllowBlobPublicAccess $false `
        -MinimumTlsVersion "TLS1_2" `
        -PublicNetworkAccess "Disabled" `
        -InfrastructureEncryption "Enabled" `
        -Tag @{ env="lab"; owner="ehab" } | Out-Null
    $st = Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageName
} else {
    Update-AzStorageAccount `
        -ResourceGroupName $ResourceGroup `
        -Name $StorageName `
        -EnableHttpsTrafficOnly $true `
        -AllowBlobPublicAccess $false `
        -MinimumTlsVersion "TLS1_2" `
        -PublicNetworkAccess "Disabled" `
        -AllowSharedKeyAccess $false `
        -InfrastructureEncryption "Enabled" | Out-Null
}
# Disable Shared Key explicitly
Update-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageName -AllowSharedKeyAccess $false | Out-Null

$StorageId = $st.Id
$BlobServiceId = "$StorageId/blobServices/default"

# --- Diagnostic settings: Blob -> Log Analytics ------------------------------
Set-AzDiagnosticSetting `
    -Name "diag-blob01" `
    -ResourceId $BlobServiceId `
    -WorkspaceId $WorkspaceResourceId `
    -Enabled $true `
    -Category @("StorageRead","StorageWrite","StorageDelete") `
    -MetricCategory @("Transaction") | Out-Null

# --- Export Subscription Activity Log -> Log Analytics -----------------------
$SubscriptionId = (Get-AzContext).Subscription.Id
Set-AzDiagnosticSetting `
    -Name "diag-activity-sub" `
    -SubscriptionId $SubscriptionId `
    -WorkspaceId $WorkspaceResourceId `
    -Enabled $true `
    -Category @("Administrative","Security","ServiceHealth","Alert","Recommendation","Policy","Autoscale","ResourceHealth") | Out-Null

# --- Optional: assign Blob Data RBAC to current user -------------------------
try {
    $Upn = (Get-AzContext).Account.Id
    $User = Get-AzADUser -UserPrincipalName $Upn -ErrorAction Stop
    New-AzRoleAssignment `
        -ObjectId $User.Id `
        -RoleDefinitionName "Storage Blob Data Contributor" `
        -Scope $StorageId `
        -ErrorAction SilentlyContinue | Out-Null
} catch {}

# --- Quick verification queries (KQL) ----------------------------------------
try {
$activity = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceCustomerId -Query @"
AzureActivity
| where TimeGenerated > ago(2h)
| summarize Count=count() by OperationNameValue, ActivityStatusValue
| order by Count desc
"@
$activity.Results | Select-Object -First 10
} catch {}

try {
$blobops = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceCustomerId -Query @"
StorageBlobLogs
| where TimeGenerated > ago(6h)
| summarize Count=count() by OperationName
| order by Count desc
"@
$blobops.Results | Select-Object -First 10
} catch {}

Write-Output "Day01 PowerShell script completed."
