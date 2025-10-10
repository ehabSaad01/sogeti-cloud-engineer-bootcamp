#!/usr/bin/env bash
set -euo pipefail

# =========================
# Day03 - Networking Foundation (CLI)
# Secure-by-default, long options, static names, no loops
# =========================

# [1] Create Resource Group
# Reason: logical container for all Day03 resources
az group create \
  --name rg-day03-network \
  --location westeurope

# [2] Create VNet + first Subnet (App)
# Reason: segmented address space; /16 VNet with /24 subnets for isolation
az network vnet create \
  --resource-group rg-day03-network \
  --name vnet03weu \
  --location westeurope \
  --address-prefixes 10.3.0.0/16 \
  --subnet-name snet03-app \
  --subnet-prefixes 10.3.0.0/24

# [3] Create second Subnet (DB)
# Reason: separate data tier to reduce blast radius and simplify NSG rules
az network vnet subnet create \
  --resource-group rg-day03-network \
  --vnet-name vnet03weu \
  --name snet03-db \
  --address-prefixes 10.3.1.0/24

# [4] Create NSGs (App, DB)
# Reason: enforce L3/L4 policy at subnet boundary (recommended)
az network nsg create \
  --resource-group rg-day03-network \
  --name nsg03weu \
  --location westeurope

az network nsg create \
  --resource-group rg-day03-network \
  --name nsg03dbweu \
  --location westeurope

# [5] Associate NSGs to subnets
# Reason: subnet-level enforcement; NIC-level left empty for simplicity
az network vnet subnet update \
  --resource-group rg-day03-network \
  --vnet-name vnet03weu \
  --name snet03-app \
  --network-security-group nsg03weu

az network vnet subnet update \
  --resource-group rg-day03-network \
  --vnet-name vnet03weu \
  --name snet03-db \
  --network-security-group nsg03dbweu

# [6] App NSG inbound HTTP allow (80/TCP)
# Reason: enable public HTTP test; priority 200 (lower is higher priority)
az network nsg rule create \
  --resource-group rg-day03-network \
  --nsg-name nsg03weu \
  --name allow-http-80 \
  --priority 200 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "*" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 80

# [7] Create ASGs (App, DB)
# Reason: dynamic grouping for NICs; rules target groups instead of IPs
az network asg create \
  --resource-group rg-day03-network \
  --name asg03-app \
  --location westeurope

az network asg create \
  --resource-group rg-day03-network \
  --name asg03-db \
  --location westeurope

# [8] DB NSG rule: allow from asg03-app to asg03-db on 1433/TCP
# Reason: permit only App -> DB SQL-like traffic; rest will be denied
az network nsg rule create \
  --resource-group rg-day03-network \
  --nsg-name nsg03dbweu \
  --name allow-sql-from-asg \
  --priority 200 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-asgs asg03-app \
  --destination-asgs asg03-db \
  --destination-port-ranges 1433

# [9] DB NSG explicit deny-all (safety net)
# Reason: enforce default-deny after explicit allows
az network nsg rule create \
  --resource-group rg-day03-network \
  --nsg-name nsg03dbweu \
  --name deny-all-inbound \
  --priority 300 \
  --direction Inbound \
  --access Deny \
  --protocol "*" \
  --source-address-prefixes "*" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges "*"

# [10] Public IP (Standard, Static)
# Reason: stable public endpoint; Standard SKU is more secure
az network public-ip create \
  --resource-group rg-day03-network \
  --name pip03weu \
  --location westeurope \
  --sku Standard \
  --allocation-method Static \
  --version IPv4

# [11] NIC for App tier (attach ASG + Public IP)
# Reason: single NIC with one IPv4 config; attach ASG and PIP at IP-config
az network nic create \
  --resource-group rg-day03-network \
  --name nic03weu \
  --location westeurope \
  --vnet-name vnet03weu \
  --subnet snet03-app \
  --ip-config-name Ipv4config

az network nic ip-config update \
  --resource-group rg-day03-network \
  --nic-name nic03weu \
  --name Ipv4config \
  --application-security-groups asg03-app \
  --public-ip-address pip03weu

# [12] NIC for DB tier (private only, attach ASG)
# Reason: no public exposure for DB
az network nic create \
  --resource-group rg-day03-network \
  --name nic03dbweu \
  --location westeurope \
  --vnet-name vnet03weu \
  --subnet snet03-db \
  --ip-config-name ipconfig1

az network nic ip-config update \
  --resource-group rg-day03-network \
  --nic-name nic03dbweu \
  --name ipconfig1 \
  --application-security-groups asg03-db

# [13] VM for App tier (use existing NIC; no implicit inbound rules)
# Reason: reuse prepared NIC; do not open inbound ports at VM creation
az vm create \
  --resource-group rg-day03-network \
  --name vm03weu \
  --location westeurope \
  --nics nic03weu \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --authentication-type Password \
  --admin-username azureuser \
  --admin-password "Replace_With_Strong_Password_123!" \
  --tags tier=app env=lab day=03

# [14] VM for DB tier (no Public IP)
# Reason: private-only database server
az vm create \
  --resource-group rg-day03-network \
  --name vm03dbweu \
  --location westeurope \
  --nics nic03dbweu \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --authentication-type Password \
  --admin-username azureuser \
  --admin-password "Replace_With_Strong_Password_123!" \
  --tags tier=db env=lab day=03

# [15] Output public IP for quick test
# Reason: convenience to retrieve current public IPv4
az network public-ip show \
  --resource-group rg-day03-network \
  --name pip03weu \
  --query "ipAddress" \
  --output tsv

