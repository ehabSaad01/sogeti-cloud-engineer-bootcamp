# Day02 — Governance: Resource Groups, Policy, RBAC

## Goal
Establish governance before workloads: enforce regions, enforce tags, and scope permissions to the resource group.

## What this lab includes
- **RG:** Dedicated training RG in West Europe with tags.
- **Policy (subscription):** *Allowed locations* → only `westeurope`.
- **Policy (RG scope):** *Require a tag and its value on resources* → `owner=ehab`.
- **RBAC (RG):** Assign **Contributor** to the signed-in user.

## Files
- `day02-governance-cli.sh` — Azure CLI, long options, no variables, inline ID retrieval.
- `day02-governance-powershell.ps1` — Az PowerShell, secure-by-default, comments in English.
- This `README.md` — Summary and rationale.

## Rationale
- **Least privilege:** Grant Contributor on the RG instead of Owner or subscription-wide roles.
- **Compliance-by-default:** Policies block out-of-region deployments and enforce tagging for cost ownership.
- **Automatable:** Scripts are ready for pipelines. No external files or temp variables required.

## Notes
- The built-in policy IDs used:
  - Allowed locations: `e56962a6-4747-49cd-b67b-bf8b01975c4c`
  - Require a tag and its value on resources: `1e30110a-5ceb-460c-a204-c1c3969c6d62`
- Replace nothing — scripts inline-resolve subscription and user IDs.
