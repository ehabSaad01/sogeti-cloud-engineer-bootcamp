#!/usr/bin/env bash
# Day02 Governance - Azure CLI
# Goal: Enforce governance with Resource Group + Policy + RBAC. Long options only. No variables. Inline ID retrieval.

set -euo pipefail

# --- 1) Create Resource Group -----------------------------------------------
# Creates the training resource group in West Europe with tracking tags.
az group create   --name rg-day02-governance-cli   --location westeurope   --tags env=training owner=ehab day=02

# --- 2) Assign Policy: Allowed locations at Subscription scope ---------------
# Enforces that resources can be deployed only in West Europe.
# Uses built-in policy definition GUID for "Allowed locations".
az policy assignment create   --name allowed-locations-cli   --display-name "Allowed locations - West Europe only"   --scope /subscriptions/$(az account show --query id --output tsv)   --policy e56962a6-4747-49cd-b67b-bf8b01975c4c   --params '{"listOfAllowedLocations":{"value":["westeurope"]}}'

# --- 3) Assign Policy: Require a tag and its value at RG scope ---------------
# Enforces tag 'owner=ehab' on resources within the RG (definition targets resources, not resource groups).
# Built-in policy definition GUID: "Require a tag and its value on resources".
az policy assignment create   --name require-owner-tag-cli   --display-name "Require tag owner=ehab on resources"   --scope /subscriptions/$(az account show --query id --output tsv)/resourceGroups/rg-day02-governance-cli   --policy 1e30110a-5ceb-460c-a204-c1c3969c6d62   --params '{"tagName":{"value":"owner"},"tagValue":{"value":"ehab"}}'

# --- 4) RBAC: Assign Contributor on RG to the signed-in user -----------------
# Grants create/update permissions on the RG to the current user without giving Owner.
az role assignment create   --role Contributor   --assignee-object-id $(az ad signed-in-user show --query id --output tsv)   --assignee-principal-type User   --scope /subscriptions/$(az account show --query id --output tsv)/resourceGroups/rg-day02-governance-cli

echo "Day02 governance via CLI: completed."
