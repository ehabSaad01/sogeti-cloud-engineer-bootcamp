#!/usr/bin/env bash
# Purpose: Day01 secure monitoring baseline via Azure CLI (idempotent)
# Notes: Long options only. Inline values. No temp files or persistent vars.

set -euo pipefail

echo "[1/6] Ensure resource group..."
az group create \
  --name "rg-day01-foundation" \
  --location "westeurope" \
  --tags "env=lab" "owner=ehab" \
  --output none

echo "[2/6] Ensure Log Analytics workspace..."
az monitor log-analytics workspace create \
  --resource-group "rg-day01-foundation" \
  --workspace-name "law01weu" \
  --location "westeurope" \
  --sku "PerGB2018" \
  --output none

echo "[3/6] Ensure secure StorageV2 account (create or enforce)..."
az storage account create \
  --name "stlog01weu" \
  --resource-group "rg-day01-foundation" \
  --location "westeurope" \
  --sku "Standard_GRS" \
  --kind "StorageV2" \
  --https-only true \
  --allow-blob-public-access false \
  --min-tls-version "TLS1_2" \
  --public-network-access "Disabled" \
  --tags "env=lab" "owner=ehab" \
  --output none || true

az storage account update \
  --name "stlog01weu" \
  --resource-group "rg-day01-foundation" \
  --allow-shared-key-access false \
  --output none

echo "[4/6] Diagnostic settings: Blob -> Log Analytics (create or update)..."
az monitor diagnostic-settings create \
  --name "diag-blob01" \
  --resource "$(az storage account show --resource-group "rg-day01-foundation" --name "stlog01weu" --query "id" --output tsv)/blobServices/default" \
  --workspace "$(az monitor log-analytics workspace show --resource-group "rg-day01-foundation" --workspace-name "law01weu" --query "id" --output tsv)" \
  --logs '[{"category":"StorageRead","enabled":true},{"category":"StorageWrite","enabled":true},{"category":"StorageDelete","enabled":true}]' \
  --metrics '[{"category":"Transaction","enabled":true,"retentionPolicy":{"enabled":false,"days":0}}]' \
  --output none || az monitor diagnostic-settings update \
       --name "diag-blob01" \
       --resource "$(az storage account show --resource-group "rg-day01-foundation" --name "stlog01weu" --query "id" --output tsv)/blobServices/default" \
       --workspace "$(az monitor log-analytics workspace show --resource-group "rg-day01-foundation" --workspace-name "law01weu" --query "id" --output tsv)" \
       --logs '[{"category":"StorageRead","enabled":true},{"category":"StorageWrite","enabled":true},{"category":"StorageDelete","enabled":true}]' \
       --metrics '[{"category":"Transaction","enabled":true,"retentionPolicy":{"enabled":false,"days":0}}]' \
       --output none

echo "[5/6] Export Activity Log at subscription scope -> Log Analytics (create or update)..."
az monitor diagnostic-settings subscription create \
  --name "diag-activity-sub" \
  --location "global" \
  --workspace "$(az monitor log-analytics workspace show --resource-group "rg-day01-foundation" --workspace-name "law01weu" --query "id" --output tsv)" \
  --logs '[{"category":"Administrative","enabled":true},{"category":"Security","enabled":true},{"category":"ServiceHealth","enabled":true},{"category":"Alert","enabled":true},{"category":"Recommendation","enabled":true},{"category":"Policy","enabled":true},{"category":"Autoscale","enabled":true},{"category":"ResourceHealth","enabled":true}]' \
  --output none || az monitor diagnostic-settings subscription update \
       --name "diag-activity-sub" \
       --location "global" \
       --workspace "$(az monitor log-analytics workspace show --resource-group "rg-day01-foundation" --workspace-name "law01weu" --query "id" --output tsv)" \
       --logs '[{"category":"Administrative","enabled":true},{"category":"Security","enabled":true},{"category":"ServiceHealth","enabled":true},{"category":"Alert","enabled":true},{"category":"Recommendation","enabled":true},{"category":"Policy","enabled":true},{"category":"Autoscale","enabled":true},{"category":"ResourceHealth","enabled":true}]' \
       --output none

echo "[6/6] Quick verification (tables may be empty if no fresh events yet)..."
az monitor log-analytics query \
  --workspace "$(az monitor log-analytics workspace show --resource-group "rg-day01-foundation" --workspace-name "law01weu" --query "customerId" --output tsv)" \
  --analytics-query "AzureActivity | where TimeGenerated > ago(2h) | summarize Count=count() by OperationNameValue, ActivityStatusValue | top 5 by Count desc" \
  --output table || true

az monitor log-analytics query \
  --workspace "$(az monitor log-analytics workspace show --resource-group "rg-day01-foundation" --workspace-name "law01weu" --query "customerId" --output tsv)" \
  --analytics-query "StorageBlobLogs | where TimeGenerated > ago(6h) | summarize Count=count() by OperationName | top 5 by Count desc" \
  --output table || true

echo "Done."
