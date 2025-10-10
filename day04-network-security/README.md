# Day04 — Network Security (NSG, ASG, Service Tags, VNet Flow Logs)

## Goal
Harden the network plane using subnet-level NSGs, ASGs for intent-based targeting, and Virtual Network Flow Logs with Traffic Analytics.

## Architecture (high level)
- VNet: vnet04weu (10.40.0.0/16)
- Subnets: snet-web04 / snet-app04 / snet-db04 / AzureBastionSubnet
- NSGs: nsg-web04, nsg-app04, nsg-db04
- ASGs: asg-web04, asg-app04, asg-db04
- Log Analytics: logw04weu + Traffic Analytics
- Storage for flow logs: stnsg04weu
- Access via Azure Bastion only (no Public IPs)

## Security defaults
- Deny-by-default for east-west, explicit allow only:
  - Internet → asg-web04 : 443
  - asg-web04 → asg-app04 : 8080
  - asg-app04 → asg-db04 : 1433 (example)
- SSH from AzureBastionSubnet (10.40.100.0/27) to asg-web04 : 22
- No Public IPs on NICs/VMs
- Storage: Disable Blob anonymous access; allow trusted Microsoft services

## Portal checklist
1) RG: rg-day04-network-security
2) LA Workspace: logw04weu
3) Storage: stnsg04weu (secure config)
4) Network Watcher + VNet Flow Logs on vnet04weu
5) VNet + Subnets + Bastion subnet
6) NSGs + ASGs + rules
7) NICs bound to ASGs
8) VMs (Ubuntu 22.04 LTS) via existing NICs
9) Bastion for secure access

## CLI/PowerShell files
- cli.sh — long options, secure-by-default
- powershell.ps1 — clear cmdlets and parameters
- Both scripts are non-destructive and include cleanup notes.

## Cleanup
Delete RG `rg-day04-network-security` after testing to stop all costs.
