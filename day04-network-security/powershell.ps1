# Day04 — Network Security (NSG, ASG, Service Tags, VNet Flow Logs)
# Purpose: Recreate Day04 via Az PowerShell with secure-by-default settings.
# Notes: No Public IPs on NICs/VMs. Access via Azure Bastion. Long, clear parameters.

Set-StrictMode -Version Latest

# ----- Parameters -----
$rg  = 'rg-day04-network-security'   # Resource Group
$loc = 'westeurope'                  # Region

# ----- Resource Group -----
# Creates the lab resource group with clear tags.
New-AzResourceGroup `
  -Name $rg `
  -Location $loc `
  -Tag @{ env = 'lab'; owner = 'ehab'; day = '04' } | Out-Null

# ----- Log Analytics Workspace -----
# Hosts Traffic Analytics for Virtual Network Flow Logs.
New-AzOperationalInsightsWorkspace `
  -ResourceGroupName $rg `
  -Name 'logw04weu' `
  -Location $loc `
  -Sku 'PerGB2018' | Out-Null

# ----- Storage Account for Flow Logs -----
# StorageV2, TLS 1.2, HTTPS only, and public blob access disabled.
New-AzStorageAccount `
  -ResourceGroupName $rg `
  -Name 'stnsg04weu' `
  -Location $loc `
  -SkuName 'Standard_LRS' `
  -Kind 'StorageV2' `
  -EnableHttpsTrafficOnly:$true `
  -MinimumTlsVersion 'TLS1_2' `
  -AllowBlobPublicAccess:$false | Out-Null
# (Optional hardening after network lockdown):
# Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $rg -Name 'stnsg04weu' -Bypass AzureServices

# ----- Network Watcher (ensure enabled in region) -----
$nw = Get-AzNetworkWatcher -Location $loc -ErrorAction SilentlyContinue
if (-not $nw) {
  New-AzNetworkWatcher -Name "NetworkWatcher_westeurope" -ResourceGroupName "NetworkWatcherRG" -Location $loc | Out-Null
}

# ----- Virtual Network + Subnets -----
$vnet = New-AzVirtualNetwork `
  -ResourceGroupName $rg `
  -Name 'vnet04weu' `
  -Location $loc `
  -AddressPrefix '10.40.0.0/16'

Add-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name 'snet-web04' -AddressPrefix '10.40.1.0/24' | Out-Null
Add-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name 'snet-app04' -AddressPrefix '10.40.2.0/24' | Out-Null
Add-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name 'snet-db04'  -AddressPrefix '10.40.3.0/24' | Out-Null
Add-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name 'AzureBastionSubnet' -AddressPrefix '10.40.100.0/27' | Out-Null
$vnet = Set-AzVirtualNetwork -VirtualNetwork $vnet

# ----- ASGs -----
$asgWeb = New-AzApplicationSecurityGroup -ResourceGroupName $rg -Name 'asg-web04' -Location $loc
$asgApp = New-AzApplicationSecurityGroup -ResourceGroupName $rg -Name 'asg-app04' -Location $loc
$asgDb  = New-AzApplicationSecurityGroup -ResourceGroupName $rg -Name 'asg-db04'  -Location $loc

# ----- NSGs -----
$nsgWeb = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $loc -Name 'nsg-web04'
$nsgApp = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $loc -Name 'nsg-app04'
$nsgDb  = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $loc -Name 'nsg-db04'

# NSG rules: Internet -> Web (443)
$nsgWeb = Add-AzNetworkSecurityRuleConfig `
  -NetworkSecurityGroup $nsgWeb `
  -Name 'allow-https-web' `
  -Description 'Allow HTTPS to web ASG' `
  -Access 'Allow' -Protocol 'Tcp' -Direction 'Inbound' -Priority 100 `
  -SourceAddressPrefix 'Internet' -SourcePortRange '*' `
  -DestinationApplicationSecurityGroup $asgWeb -DestinationPortRange 443
$nsgWeb = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgWeb

# NSG rules: Web -> App (8080) then deny rest of VNet
$nsgApp = Add-AzNetworkSecurityRuleConfig `
  -NetworkSecurityGroup $nsgApp `
  -Name 'allow-web-to-app-8080' `
  -Description 'Web to App on 8080' `
  -Access 'Allow' -Protocol 'Tcp' -Direction 'Inbound' -Priority 100 `
  -SourceApplicationSecurityGroup $asgWeb -SourcePortRange '*' `
  -DestinationApplicationSecurityGroup $asgApp -DestinationPortRange 8080
$nsgApp = Add-AzNetworkSecurityRuleConfig `
  -NetworkSecurityGroup $nsgApp `
  -Name 'deny-vnet-in' `
  -Description 'Deny any VNet inbound' `
  -Access 'Deny' -Protocol '*' -Direction 'Inbound' -Priority 200 `
  -SourceAddressPrefix 'VirtualNetwork' -SourcePortRange '*' `
  -DestinationAddressPrefix '*' -DestinationPortRange '*'
$nsgApp = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgApp

# NSG rules: App -> DB (1433) then deny rest of VNet
$nsgDb = Add-AzNetworkSecurityRuleConfig `
  -NetworkSecurityGroup $nsgDb `
  -Name 'allow-app-to-db-1433' `
  -Description 'App to DB on 1433' `
  -Access 'Allow' -Protocol 'Tcp' -Direction 'Inbound' -Priority 100 `
  -SourceApplicationSecurityGroup $asgApp -SourcePortRange '*' `
  -DestinationApplicationSecurityGroup $asgDb -DestinationPortRange 1433
$nsgDb = Add-AzNetworkSecurityRuleConfig `
  -NetworkSecurityGroup $nsgDb `
  -Name 'deny-vnet-in' `
  -Description 'Deny any VNet inbound' `
  -Access 'Deny' -Protocol '*' -Direction 'Inbound' -Priority 200 `
  -SourceAddressPrefix 'VirtualNetwork' -SourcePortRange '*' `
  -DestinationAddressPrefix '*' -DestinationPortRange '*'
$nsgDb = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgDb

# ----- Associate NSGs with Subnets -----
$snetWeb = Get-AzVirtualNetworkSubnetConfig -Name 'snet-web04' -VirtualNetwork $vnet
$snetApp = Get-AzVirtualNetworkSubnetConfig -Name 'snet-app04' -VirtualNetwork $vnet
$snetDb  = Get-AzVirtualNetworkSubnetConfig -Name 'snet-db04'  -VirtualNetwork $vnet

Set-AzVirtualNetworkSubnetConfig -Name $snetWeb.Name -VirtualNetwork $vnet -AddressPrefix $snetWeb.AddressPrefix -NetworkSecurityGroup $nsgWeb | Out-Null
Set-AzVirtualNetworkSubnetConfig -Name $snetApp.Name -VirtualNetwork $vnet -AddressPrefix $snetApp.AddressPrefix -NetworkSecurityGroup $nsgApp | Out-Null
Set-AzVirtualNetworkSubnetConfig -Name $snetDb.Name  -VirtualNetwork $vnet -AddressPrefix $snetDb.AddressPrefix  -NetworkSecurityGroup $nsgDb  | Out-Null
$vnet = Set-AzVirtualNetwork -VirtualNetwork $vnet

# ----- NICs (no Public IPs) + bind to ASGs -----
$nicWeb = New-AzNetworkInterface -ResourceGroupName $rg -Name 'nic-web04' -Location $loc -SubnetId $snetWeb.Id -ApplicationSecurityGroup $asgWeb
$nicApp = New-AzNetworkInterface -ResourceGroupName $rg -Name 'nic-app04' -Location $loc -SubnetId $snetApp.Id -ApplicationSecurityGroup $asgApp
$nicDb  = New-AzNetworkInterface -ResourceGroupName $rg -Name 'nic-db04'  -Location $loc -SubnetId $snetDb.Id  -ApplicationSecurityGroup $asgDb

# ----- Azure Bastion (Standard SKU) -----
$pipBast = New-AzPublicIpAddress -ResourceGroupName $rg -Name 'pip-bast04weu' -Location $loc -Sku 'Standard' -AllocationMethod 'Static'
New-AzBastion -ResourceGroupName $rg -Name 'bast04weu' -Location $loc -VirtualNetwork $vnet -PublicIpAddress $pipBast -Sku 'Standard' | Out-Null

# NSG rule: Bastion SSH to Web only
$nsgWeb = Add-AzNetworkSecurityRuleConfig `
  -NetworkSecurityGroup $nsgWeb `
  -Name 'allow-bastion-ssh-web' `
  -Description 'SSH from AzureBastionSubnet only' `
  -Access 'Allow' -Protocol 'Tcp' -Direction 'Inbound' -Priority 110 `
  -SourceAddressPrefix '10.40.100.0/27' -SourcePortRange '*' `
  -DestinationApplicationSecurityGroup $asgWeb -DestinationPortRange 22
$nsgWeb = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgWeb

# ----- Virtual Network Flow Logs -----
# Create via portal or latest CLI/REST. Point to stnsg04weu and enable Traffic Analytics to logw04weu.

# ----- Optional: VMs (Ubuntu 22.04 LTS) using existing NICs, SSH key auth -----
$pubKey = (Get-Content -Path "$HOME/.ssh/id_rsa.pub" -Raw)
New-AzVM -ResourceGroupName $rg -Name 'vm-web04' -Location $loc -Size 'Standard_B1s' -Image 'Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest' -NetworkInterface $nicWeb -AdminUsername 'azureuser' -AuthenticationType 'sshPublicKey' -SshKeyValue $pubKey -Tag @{ env='lab'; owner='ehab'; day='04' } | Out-Null
New-AzVM -ResourceGroupName $rg -Name 'vm-app04' -Location $loc -Size 'Standard_B1s' -Image 'Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest' -NetworkInterface $nicApp -AdminUsername 'azureuser' -AuthenticationType 'sshPublicKey' -SshKeyValue $pubKey -Tag @{ env='lab'; owner='ehab'; day='04' } | Out-Null
New-AzVM -ResourceGroupName $rg -Name 'vm-db04'  -Location $loc -Size 'Standard_B1s' -Image 'Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest' -NetworkInterface $nicDb  -AdminUsername 'azureuser' -AuthenticationType 'sshPublicKey' -SshKeyValue $pubKey -Tag @{ env='lab'; owner='ehab'; day='04' } | Out-Null

# ----- Cleanup helper (commented) -----
# Remove-AzResourceGroup -Name $rg -Force
