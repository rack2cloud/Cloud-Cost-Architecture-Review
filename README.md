# Cloud Cost Architecture Review

![Pillar](https://img.shields.io/badge/Pillar-Cloud%20Cost%20Architecture-a78bfa)
![Status](https://img.shields.io/badge/Status-Production--Ready-a78bfa)
![License](https://img.shields.io/badge/License-MIT-green)

A lightweight topology collection script for the Rack2Cloud Cost Architecture Review. Collects structural metadata about workload placement, ownership density, control plane spread, and cross-region architecture patterns. No billing exports. No credentials transmitted. No optimization recommendations generated locally.

Upload the output JSON to [rack2cloud.com/audits/cost-architecture-review/](https://rack2cloud.com/audits/cost-architecture-review/) as an optional enrichment to your intake — or submit the intake questionnaire directly without running the script.

---

## >_ The Architectural Reality

### The Problem

Cloud cost programs fail not because of poor execution but because of Cost Authority Inversion — the condition where the team generating infrastructure cost through architectural decisions is not the team accountable for the resulting spend.

By the time FinOps opens the dashboard, most of the spend it finds is already structurally committed: workloads placed, replication paths chosen, control planes provisioned. The invoice is a reporting artifact. It documents architectural decisions that closed weeks or months before the bill was generated.

### What This Script Does

`Invoke-R2CCostTopology.ps1` collects structural topology metadata — environment shape, ownership density, data gravity signals, and control plane spread — that helps map the architectural patterns generating spend. It does not analyze billing data, generate savings estimates, or produce optimization recommendations. The interpretation is done by The Architect, not the script.

This is a topology intake accelerator, not a diagnostic engine.

---

## 🛡️ The InfoSec Guarantee: Zero Exfiltration

Before running the live collection, verify exactly what this script does using the `-DryRun` flag.

```powershell
.\Invoke-R2CCostTopology.ps1 -DryRun
```

*This executes a simulated run with zero API calls. It prints every field name and data type that would be written to the JSON. Review it. Audit the source code. Only run live when you are satisfied.*

### ✅ Collected — Structural Metadata Only

| Section | What Is Collected |
|---|---|
| **Environment Shape** | Provider count, region count, account/subscription count, Kubernetes cluster count, managed DB count, VPC/VNet count |
| **Ownership Density** | % resources missing owner tag, % missing environment tag, % resources older than 180 days with no lifecycle tag, % unattached resources |
| **Data Gravity Signals** | Inter-region transfer enabled (boolean), peering count, NAT gateway count, public egress service count, CDN usage presence (boolean), replication service presence (boolean) |
| **Control Plane Spread** | CI/CD platform count, monitoring stack count, ingress controller count, Kubernetes distro count, IaC tooling count |

### ❌ Never Collected

- Billing data, cost exports, or invoice line items
- Subscription IDs or Tenant IDs *(represented as a one-way SHA-256 hash locally)*
- IP addresses (public or private)
- Resource names, display names, or tag values
- User principal names or email addresses
- Secrets, keys, connection strings, or credentials
- Any payload data from your actual workloads
- Savings estimates or optimization recommendations

---

## ⚙️ Prerequisites & Execution

### Option A: Cloud Shell (Recommended)

Cloud Shell is pre-authenticated for your provider environment. No local module installation required.

**AWS:** Open [cloudshell.amazonaws.com](https://cloudshell.amazonaws.com) or launch from the AWS Console. Select PowerShell or Bash mode. Upload or clone this script.

**Azure:** Open [shell.azure.com](https://shell.azure.com) or launch Cloud Shell from the Azure Portal. Select PowerShell mode.

**GCP:** Open Cloud Shell from the GCP Console. PowerShell 7+ available via `sudo apt install -y powershell`.

### Option B: Local PowerShell

**Requirements:**
- PowerShell 7+
- Provider-appropriate module set (see below)

**AWS:**
```powershell
Install-Module AWS.Tools.Common, AWS.Tools.EC2, AWS.Tools.EKS, AWS.Tools.RDS -Scope CurrentUser -Force
```

**Azure:**
```powershell
Install-Module Az.Accounts, Az.Resources, Az.Network, Az.Compute, Az.ContainerService -Scope CurrentUser -Force
Connect-AzAccount
```

**GCP:**
```powershell
# Requires gcloud CLI authenticated
# Install PowerShell GCP module
Install-Module GoogleCloud -Scope CurrentUser -Force
```

---

## Usage Commands

```powershell
# 1. Verify collection scope before execution (No API calls)
.\Invoke-R2CCostTopology.ps1 -DryRun

# 2. Run against current authenticated context
.\Invoke-R2CCostTopology.ps1

# 3. Target a specific account or subscription
.\Invoke-R2CCostTopology.ps1 -AccountId "123456789012"         # AWS
.\Invoke-R2CCostTopology.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000"  # Azure
.\Invoke-R2CCostTopology.ps1 -ProjectId "my-gcp-project"       # GCP

# 4. Specify output directory
.\Invoke-R2CCostTopology.ps1 -OutputPath "~/topology-exports"

# 5. Multi-account / multi-subscription sweep (outputs one file per account)
.\Invoke-R2CCostTopology.ps1 -AllAccounts
```

---

## 📊 The Output Pipeline

### 1. The Console Summary

When you run the script live, a topology summary prints immediately — before uploading anything:

```
  ════════════════════════════════════════════════════
  RACK2CLOUD >_ COST TOPOLOGY COLLECTION — COMPLETE
  ════════════════════════════════════════════════════

  ENVIRONMENT SHAPE:
    Providers detected:         2
    Regions in use:             4
    Accounts / Subscriptions:   3
    Kubernetes clusters:        6
    Managed databases:          9
    VPCs / VNets:               11

  OWNERSHIP DENSITY:
    Resources missing owner tag:      61%
    Resources missing env tag:        48%
    Untagged resources >180 days:     34%
    Unattached resource rate:         12%

  DATA GRAVITY SIGNALS:
    Inter-region transfer:    ENABLED
    Peering connections:      7
    NAT gateways:             5
    Public egress services:   3
    CDN coverage:             PARTIAL
    Replication services:     DETECTED

  CONTROL PLANE SPREAD:
    CI/CD platforms:          3
    Monitoring stacks:        4
    Ingress controllers:      5
    Kubernetes distros:       2
    IaC tooling:              2

  ────────────────────────────────────────────────────
  Payload written: r2c_topology_payload.json
  Review the file before uploading.

  NEXT STEP:
  Include r2c_topology_payload.json with your intake at:
  rack2cloud.com/audits/cost-architecture-review/
  ════════════════════════════════════════════════════
```

---

### 2. The Payload: r2c_topology_payload.json

The script writes a single file to your working directory (or the path specified by `-OutputPath`).

**Review it before uploading.** Open it in any text editor. Confirm that no IPs, resource names, account identifiers, or billing data are present. The file contains only counts, booleans, percentages, and a one-way SHA-256 hash fingerprint — not raw identifiers.

<details>
<summary><strong>View Sample JSON Payload</strong></summary>

```json
{
  "schema_version": "1.0.0",
  "generated_at_utc": "2026-05-09T10:00:00Z",
  "environment_fingerprint": "b7e22a4f91d3",
  "environment_shape": {
    "provider_count": 2,
    "region_count": 4,
    "account_subscription_count": 3,
    "kubernetes_cluster_count": 6,
    "managed_db_count": 9,
    "vpc_vnet_count": 11
  },
  "ownership_density": {
    "resources_missing_owner_tag_pct": 61.2,
    "resources_missing_env_tag_pct": 47.8,
    "untagged_resources_over_180d_pct": 34.1,
    "unattached_resource_rate_pct": 12.4
  },
  "data_gravity_signals": {
    "inter_region_transfer_enabled": true,
    "peering_connection_count": 7,
    "nat_gateway_count": 5,
    "public_egress_service_count": 3,
    "cdn_usage_present": true,
    "replication_service_present": true
  },
  "control_plane_spread": {
    "cicd_platform_count": 3,
    "monitoring_stack_count": 4,
    "ingress_controller_count": 5,
    "kubernetes_distro_count": 2,
    "iac_tooling_count": 2
  }
}
```

</details>

---

### 3. The Cost Architecture Review

Submit your intake questionnaire at [rack2cloud.com/audits/cost-architecture-review/](https://rack2cloud.com/audits/cost-architecture-review/). Include `r2c_topology_payload.json` as optional topology enrichment. The Architect reviews every submission before engagement approval.

The Cost Architecture Brief is a 5–7 page architectural findings document that includes:

- **Cost Authority Map** — ownership topology across the four architectural domains
- **Workload Placement & Data Gravity Analysis** — where placement decisions are generating spend
- **Control Plane Sprawl Assessment** — idle and over-provisioned control plane architecture
- **Egress & Cross-Region Exposure Review** — traffic patterns generating persistent spend
- **Prioritized Remediation Sequence** — ordered by architectural leverage, not invoice line items

---

## Scoring Framework

The topology payload informs four analytical domains in the Cost Architecture Review:

| Domain | Topology Signals Used | What It Surfaces |
|---|---|---|
| Cost Authority & Ownership | Ownership density metrics, untagged resource rates | Where cost accountability gaps are widest |
| Workload Placement | Data gravity signals, region count, peering topology | Placement-driven egress and replication exposure |
| Control Plane Sprawl | Control plane spread counts, cluster and distro count | Architectural debt generating idle infrastructure cost |
| Egress & Cross-Region | NAT gateway count, inter-region transfer, replication presence | Traffic patterns creating committed spend |

---

## 🏗️ Required Permissions

The script requires **Reader / Viewer** role on the target account, subscription, or project. It does not require Contributor, Owner, write permissions, or billing API access. It makes no changes to your environment.

**AWS:** `ReadOnlyAccess` managed policy or equivalent.
**Azure:** `Reader` role on the target subscription. No Graph API access required.
**GCP:** `Viewer` role (`roles/viewer`) on the target project.

---

## 🔍 Audit the Source

This script is fully open source. Every line is reviewable. There are no obfuscated sections, no external network calls, no telemetry, and no data transmission beyond the provider's own resource management API — the same API used by each provider's native console.

If you identify a data collection concern or a bug, open an issue or submit a PR.

---

## License

MIT License — see [LICENSE](LICENSE)

---

## About

Built by [The Architect](https://rack2cloud.com) — 25+ years of enterprise infrastructure delivery across financial services, healthcare, manufacturing, and public sector.

**rack2cloud.com** | [Cloud Strategy Architecture](https://rack2cloud.com/cloud-strategy/) | [Cost Architecture Review](https://rack2cloud.com/audits/cost-architecture-review/) | [Contact](https://rack2cloud.com/contact)
