<# ===============================
 Day03 - Networking Foundation (PowerShell)
 Secure-by-default, long params, no loops, clear English comments
 Requires: Az.Accounts, Az.Network, Az.Compute
================================ #>

# [0] Parameters (replace password before use)
$Location = "westeurope"
$RgName   = "rg-day03-network"
$VnetName = "vnet03weu"
$SubnetAppName = "snet03-app"
$SubnetDbName  = "snet03-db"
$NsgAppName = "nsg03weu"
$NsgDbName  = "nsg03dbweu"
$AsgAppName = "asg03-app"
$AsgDbName  = "asg03-db"
$PipName    = "pip03weu"
$NicAppName = "nic03weu"
$NicDbName  = "nic03dbweu"
$VmAppName  = "vm03weu"
$VmDbName   = "vm03dbweu"
$AdminUser  = "azureuser"
$AdminPass  = (ConvertTo-SecureString "Replace_With_Strong_Password_123!" -AsPlainText -Force)

# [1] Create Resource Group
# Reason: logical container for all Day03 resources
New-AzResourceGroup -Name $RgName -Location $Location | Out-Null

# [2] Build VNet + Subnets (App / DB)
# Reason: /16 VNet with two /24 subnets for isolation
$subnetApp = New-AzVirtualNetworkSubnetConfig -Name $SubnetAppName -AddressPrefix "10.3.0.0/24"
$subnetDb  = New-AzVirtualNetworkSubnetConfig -Name $SubnetDbName  -AddressPrefix "10.3.1.0/24"
$vnet = New-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -Location $Location -AddressPrefix "10.3.0.0/16" -Subnet $subnetApp, $subnetDb

# [3] Create NSGs (App / DB)
# Reason: enforce L3/L4 policy at subnet boundary
$nsgApp = New-AzNetworkSecurityGroup -Name $NsgAppName -ResourceGroupName $RgName -Location $Location
$nsgDb  = New-AzNetworkSecurityGroup -Name $NsgDbName  -ResourceGroupName $RgName -Location $Location

# [4] App NSG inbound HTTP allow (80/TCP), priority 200
# Reason: enable public HTTP test to App tier
$nsgApp | Add-AzNetworkSecurityRuleConfig `
  -Name "allow-http-80" `
  -Description "Allow HTTP 80/TCP from Internet to App subnet" `
  -Access "Allow" `
  -Protocol "Tcp" `
  -Direction "Inbound" `
  -Priority 200 `
  -SourceAddressPrefix "*" `
  -SourcePortRange "*" `
  -DestinationAddressPrefix "*" `
  -DestinationPortRange 80 | Set-AzNetworkSecurityGroup | Out-Null

# [5] Create ASGs (App / DB)
# Reason: dynamic grouping for NIC-based policy
$asgApp = New-AzApplicationSecurityGroup -Name $AsgAppName -ResourceGroupName $RgName -Location $Location
$asgDb  = New-AzApplicationSecurityGroup -Name $AsgDbName  -ResourceGroupName $RgName -Location $Location

# [6] DB NSG rule: allow from asg03-app to asg03-db on 1433/TCP, then explicit deny-all
# Reason: permit only App → DB SQL-like traffic
$nsgDb | Add-AzNetworkSecurityRuleConfig `
  -Name "allow-sql-from-asg" `
  -Description "Allow 1433/TCP from asg03-app to asg03-db" `
  -Access "Allow" `
  -Protocol "Tcp" `
  -Direction "Inbound" `
  -Priority 200 `
  -SourceApplicationSecurityGroupId $asgApp.Id `
  -DestinationApplicationSecurityGroupId $asgDb.Id `
  -DestinationPortRange 1433 | Set-AzNetworkSecurityGroup | Out-Null

$nsgDb | Add-AzNetworkSecurityRuleConfig `
  -Name "deny-all-inbound" `
  -Description "Explicit deny-all inbound after specific allows" `
  -Access "Deny" `
  -Protocol "*" `
  -Direction "Inbound" `
  -Priority 300 `
  -SourceAddressPrefix "*" `
  -SourcePortRange "*" `
  -DestinationAddressPrefix "*" `
  -DestinationPortRange "*" | Set-AzNetworkSecurityGroup | Out-Null

# [7] Associate NSGs to subnets
# Reason: subnet-level enforcement (preferred)
$subnetApp = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetAppName -AddressPrefix "10.3.0.0/24" -NetworkSecurityGroup $nsgApp
$subnetDb  = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetDbName  -AddressPrefix "10.3.1.0/24" -NetworkSecurityGroup $nsgDb
$vnet | Set-AzVirtualNetwork | Out-Null

# [8] Public IP (Standard, Static)
# Reason: stable public endpoint
$pip = New-AzPublicIpAddress -Name $PipName -ResourceGroupName $RgName -Location $Location -Sku "Standard" -AllocationMethod "Static" -IpAddressVersion "IPv4"

# [9] NIC for App tier (attach ASG + Public IP)
# Reason: single IPv4 config with ASG and PIP
$ipcfgApp = New-AzNetworkInterfaceIpConfig -Name "Ipv4config" -SubnetId $subnetApp.Id -PublicIpAddressId $pip.Id -ApplicationSecurityGroupId $asgApp.Id
$nicApp = New-AzNetworkInterface -Name $NicAppName -ResourceGroupName $RgName -Location $Location -IpConfiguration $ipcfgApp

# [10] NIC for DB tier (private only, attach ASG)
# Reason: DB should not be exposed publicly
$ipcfgDb = New-AzNetworkInterfaceIpConfig -Name "ipconfig1" -SubnetId $subnetDb.Id -ApplicationSecurityGroupId $asgDb.Id
$nicDb = New-AzNetworkInterface -Name $NicDbName -ResourceGroupName $RgName -Location $Location -IpConfiguration $ipcfgDb

# [11] VM for App tier (reuse NIC; no inbound VM-level rules)
# Reason: NIC + NSG control exposure; keep VM creation minimal
$cred = New-Object System.Management.Automation.PSCredential($AdminUser, $AdminPass)
New-AzVM `
  -Name $VmAppName `
  -ResourceGroupName $RgName `
  -Location $Location `
  -Image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest" `
  -Size "Standard_B1s" `
  -Credential $cred `
  -NetworkInterface $nicApp `
  -Tag @{ tier="app"; env="lab"; day="03" } | Out-Null

# [12] VM for DB tier (private only)
# Reason: internal-only database server
New-AzVM `
  -Name $VmDbName `
  -ResourceGroupName $RgName `
  -Location $Location `
  -Image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest" `
  -Size "Standard_B1s" `
  -Credential $cred `
  -NetworkInterface $nicDb `
  -Tag @{ tier="db"; env="lab"; day="03" } | Out-Null

# [13] Output public IPv4 for quick test
# Reason: convenience to retrieve current public IPv4
(Get-AzPublicIpAddress -Name $PipName -ResourceGroupName $RgName).IpAddress
