#!/usr/bin/env bash
set -euo pipefail

# Day04 — Network Security (NSG, ASG, Service Tags, VNet Flow Logs)
# Purpose: Recreate Day04 lab resources via Azure CLI with long options and secure defaults.
# Notes:
# - No Public IPs on NICs/VMs. Access via Azure Bastion only.
# - RBAC-first model. No shared keys required to run.
# - Run in Azure Cloud Shell Bash or az CLI with an authenticated session.

# ----- Resource Group -----
# Creates the lab resource group in West Europe with clear tags.
az group create \
  --name rg-day04-network-security \
  --location westeurope \
  --tags env=lab owner=ehab day=04

# ----- Log Analytics Workspace -----
# Hosts Traffic Analytics for Virtual Network Flow Logs.
az monitor log-analytics workspace create \
  --resource-group rg-day04-network-security \
  --workspace-name logw04weu \
  --location westeurope

# ----- Storage Account for Flow Logs -----
# StorageV2, TLS 1.2, HTTPS only, and public blob access disabled.
az storage account create \
  --resource-group rg-day04-network-security \
  --name stnsg04weu \
  --location westeurope \
  --sku Standard_LRS \
  --kind StorageV2 \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

# (Optional hardening) If you later lock down networking, enable trusted MS services bypass:
# az storage account update --resource-group rg-day04-network-security --name stnsg04weu --bypass AzureServices

# ----- Network Watcher (ensure enabled in region) -----
az network watcher configure \
  --locations westeurope \
  --enabled true

# ----- Virtual Network + Subnets -----
# Creates VNet with three tiered subnets and Bastion subnet.
az network vnet create \
  --resource-group rg-day04-network-security \
  --name vnet04weu \
  --location westeurope \
  --address-prefixes 10.40.0.0/16 \
  --subnet-name snet-web04 \
  --subnet-prefix 10.40.1.0/24

az network vnet subnet create \
  --resource-group rg-day04-network-security \
  --vnet-name vnet04weu \
  --name snet-app04 \
  --address-prefixes 10.40.2.0/24

az network vnet subnet create \
  --resource-group rg-day04-network-security \
  --vnet-name vnet04weu \
  --name snet-db04 \
  --address-prefixes 10.40.3.0/24

az network vnet subnet create \
  --resource-group rg-day04-network-security \
  --vnet-name vnet04weu \
  --name AzureBastionSubnet \
  --address-prefixes 10.40.100.0/27

# ----- NSGs -----
az network nsg create \
  --resource-group rg-day04-network-security \
  --name nsg-web04 \
  --location westeurope

az network nsg create \
  --resource-group rg-day04-network-security \
  --name nsg-app04 \
  --location westeurope

az network nsg create \
  --resource-group rg-day04-network-security \
  --name nsg-db04 \
  --location westeurope

# ----- Associate NSGs with Subnets -----
az network vnet subnet update \
  --resource-group rg-day04-network-security \
  --vnet-name vnet04weu \
  --name snet-web04 \
  --network-security-group nsg-web04

az network vnet subnet update \
  --resource-group rg-day04-network-security \
  --vnet-name vnet04weu \
  --name snet-app04 \
  --network-security-group nsg-app04

az network vnet subnet update \
  --resource-group rg-day04-network-security \
  --vnet-name vnet04weu \
  --name snet-db04 \
  --network-security-group nsg-db04

# ----- ASGs -----
az network asg create \
  --resource-group rg-day04-network-security \
  --name asg-web04 \
  --location westeurope

az network asg create \
  --resource-group rg-day04-network-security \
  --name asg-app04 \
  --location westeurope

az network asg create \
  --resource-group rg-day04-network-security \
  --name asg-db04 \
  --location westeurope

# ----- NSG Rules -----
# Allow Internet -> Web on 443 to ASG
az network nsg rule create \
  --resource-group rg-day04-network-security \
  --nsg-name nsg-web04 \
  --name allow-https-web \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes Internet \
  --source-port-ranges "*" \
  --destination-asgs asg-web04 \
  --destination-port-ranges 443

# Allow Web -> App on 8080 using ASGs
az network nsg rule create \
  --resource-group rg-day04-network-security \
  --nsg-name nsg-app04 \
  --name allow-web-to-app-8080 \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-asgs asg-web04 \
  --source-port-ranges "*" \
  --destination-asgs asg-app04 \
  --destination-port-ranges 8080

# Deny any other VNet -> App traffic
az network nsg rule create \
  --resource-group rg-day04-network-security \
  --nsg-name nsg-app04 \
  --name deny-vnet-in \
  --priority 200 \
  --direction Inbound \
  --access Deny \
  --protocol "*" \
  --source-address-prefixes VirtualNetwork \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges "*"

# Allow App -> DB on 1433 using ASGs
az network nsg rule create \
  --resource-group rg-day04-network-security \
  --nsg-name nsg-db04 \
  --name allow-app-to-db-1433 \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-asgs asg-app04 \
  --source-port-ranges "*" \
  --destination-asgs asg-db04 \
  --destination-port-ranges 1433

# Deny any other VNet -> DB traffic
az network nsg rule create \
  --resource-group rg-day04-network-security \
  --nsg-name nsg-db04 \
  --name deny-vnet-in \
  --priority 200 \
  --direction Inbound \
  --access Deny \
  --protocol "*" \
  --source-address-prefixes VirtualNetwork \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges "*"

# ----- NICs (no Public IPs) -----
az network nic create \
  --resource-group rg-day04-network-security \
  --name nic-web04 \
  --location westeurope \
  --vnet-name vnet04weu \
  --subnet snet-web04 \
  --ip-forwarding false

az network nic create \
  --resource-group rg-day04-network-security \
  --name nic-app04 \
  --location westeurope \
  --vnet-name vnet04weu \
  --subnet snet-app04 \
  --ip-forwarding false

az network nic create \
  --resource-group rg-day04-network-security \
  --name nic-db04 \
  --location westeurope \
  --vnet-name vnet04weu \
  --subnet snet-db04 \
  --ip-forwarding false

# ----- Bind NICs to ASGs -----
az network nic ip-config update \
  --resource-group rg-day04-network-security \
  --nic-name nic-web04 \
  --name ipconfig1 \
  --application-security-groups asg-web04

az network nic ip-config update \
  --resource-group rg-day04-network-security \
  --nic-name nic-app04 \
  --name ipconfig1 \
  --application-security-groups asg-app04

az network nic ip-config update \
  --resource-group rg-day04-network-security \
  --nic-name nic-db04 \
  --name ipconfig1 \
  --application-security-groups asg-db04

# ----- VMs (Ubuntu 22.04 LTS), attached to existing NICs, no Public IPs -----
az vm create \
  --resource-group rg-day04-network-security \
  --location westeurope \
  --name vm-web04 \
  --nics nic-web04 \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest \
  --size Standard_B1s \
  --admin-username azureuser \
  --authentication-type ssh \
  --generate-ssh-keys \
  --tags env=lab owner=ehab day=04

az vm create \
  --resource-group rg-day04-network-security \
  --location westeurope \
  --name vm-app04 \
  --nics nic-app04 \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest \
  --size Standard_B1s \
  --admin-username azureuser \
  --authentication-type ssh \
  --generate-ssh-keys \
  --tags env=lab owner=ehab day=04

az vm create \
  --resource-group rg-day04-network-security \
  --location westeurope \
  --name vm-db04 \
  --nics nic-db04 \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest \
  --size Standard_B1s \
  --admin-username azureuser \
  --authentication-type ssh \
  --generate-ssh-keys \
  --tags env=lab owner=ehab day=04

# ----- Azure Bastion (Standard SKU) -----
az network public-ip create \
  --resource-group rg-day04-network-security \
  --name pip-bast04weu \
  --location westeurope \
  --sku Standard \
  --allocation-method Static

az network bastion create \
  --resource-group rg-day04-network-security \
  --name bast04weu \
  --location westeurope \
  --vnet-name vnet04weu \
  --public-ip-address pip-bast04weu \
  --sku Standard

# ----- NSG rule for Bastion SSH to Web only -----
az network nsg rule create \
  --resource-group rg-day04-network-security \
  --nsg-name nsg-web04 \
  --name allow-bastion-ssh-web \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes 10.40.100.0/27 \
  --source-port-ranges "*" \
  --destination-asgs asg-web04 \
  --destination-port-ranges 22

# ----- Virtual Network Flow Logs (create via portal recommended) -----
# Note: The new "Virtual network flow logs" resource may require portal or latest CLI extension.
# After creation, point logs to stnsg04weu and enable Traffic Analytics to logw04weu.

# ----- Cleanup helper (commented) -----
# az group delete --name rg-day04-network-security --yes --no-wait
