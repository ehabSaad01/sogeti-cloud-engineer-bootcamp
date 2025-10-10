# Day 03 – Networking Foundation (Azure Administrator Labs)

## 🎯 Objective
Build a secure and segmented Azure virtual network following **least privilege** and **defense-in-depth** principles.

---

## 🧠 Concept Summary
| Layer | Component | Purpose |
|-------|------------|----------|
| Network | **Virtual Network (vnet03weu)** | Private address space `10.3.0.0/16` |
| Subnet 1 | **snet03-app** | Application servers, reachable via HTTP |
| Subnet 2 | **snet03-db** | Database layer, isolated from Internet |
| Security | **NSG (nsg03weu / nsg03dbweu)** | Control inbound/outbound traffic |
| Logic | **ASG (asg03-app / asg03-db)** | Dynamic grouping for NSG rules |
| Access | **Public IP (pip03weu)** | Stable entry point for web access |
| Interface | **NICs (nic03weu / nic03dbweu)** | Network adapters binding resources |
| Compute | **VMs (vm03weu / vm03dbweu)** | Linux servers for app and DB tiers |

---

## 🧩 Implementation Steps (Portal Summary)
1. Create Resource Group `rg-day03-network`
2. Create **Virtual Network** `vnet03weu` → address space `10.3.0.0/16`
3. Add Subnets:
   - `snet03-app` → `10.3.0.0/24`
   - `snet03-db` → `10.3.1.0/24`
4. Create **NSGs**:
   - `nsg03weu` → allow inbound TCP/80
   - `nsg03dbweu` → allow TCP/1433 from `asg03-app` → `asg03-db`, deny all else
5. Associate each NSG with its subnet.
6. Create **ASGs**: `asg03-app`, `asg03-db`
7. Create **Public IP (Standard, Static)** → `pip03weu`
8. Create **NICs** and attach ASGs / Public IPs:
   - `nic03weu` → `asg03-app`, `pip03weu`
   - `nic03dbweu` → `asg03-db`
9. Create **VMs**:
   - `vm03weu` → App tier with public access
   - `vm03dbweu` → DB tier with private IP only
10. Verify:
    - HTTP access only to app VM public IP
    - SQL (1433) reachable only from app subnet

---

## 🔐 Security Principles
- **Subnet Isolation:** app ↔ db traffic only through defined NSG rules  
- **ASG-Based Rules:** eliminate static IP dependencies  
- **Standard Public IP:** prevents open inbound by default  
- **Explicit Deny:** ensures predictable traffic behavior  

---

## 🧾 Verification Commands
### From App VM
```bash
curl -I http://localhost
nc -zv 10.3.1.5 1433
