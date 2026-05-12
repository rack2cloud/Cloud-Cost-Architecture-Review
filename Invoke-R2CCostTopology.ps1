#Requires -Version 7.0
<#
.SYNOPSIS
    Rack2Cloud Cost Architecture Review — Topology Collection Script

.DESCRIPTION
    Collects structural topology metadata about workload placement, ownership density,
    control plane spread, and cross-region architecture patterns.

    No billing data. No credentials transmitted. No optimization recommendations.
    Output is counts, booleans, percentages, and a one-way SHA-256 fingerprint only.

    Upload the output JSON to rack2cloud.com/audits/cost-architecture-review/
    as optional enrichment to your intake questionnaire.

.PARAMETER DryRun
    Simulated run. Zero API calls. Prints every field name and data type that would
    be written to the JSON. Review before running live.

.PARAMETER AccountId
    AWS: Target a specific account ID. Defaults to current authenticated context.

.PARAMETER SubscriptionId
    Azure: Target a specific subscription ID. Defaults to current authenticated context.

.PARAMETER ProjectId
    GCP: Target a specific project ID. Defaults to current authenticated context.

.PARAMETER OutputPath
    Directory to write the JSON payload. Defaults to current working directory.

.PARAMETER AllAccounts
    Sweep all accessible accounts/subscriptions. Outputs one file per account.

.EXAMPLE
    # Verify collection scope — zero API calls
    .\Invoke-R2CCostTopology.ps1 -DryRun

.EXAMPLE
    # Run against current authenticated context
    .\Invoke-R2CCostTopology.ps1

.EXAMPLE
    # Target specific account
    .\Invoke-R2CCostTopology.ps1 -AccountId "123456789012"
    .\Invoke-R2CCostTopology.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000"
    .\Invoke-R2CCostTopology.ps1 -ProjectId "my-gcp-project"

.EXAMPLE
    # Specify output directory
    .\Invoke-R2CCostTopology.ps1 -OutputPath "~/topology-exports"

.EXAMPLE
    # Multi-account sweep
    .\Invoke-R2CCostTopology.ps1 -AllAccounts

.NOTES
    Schema Version : 1.0.0
    Author         : The Architect — rack2cloud.com
    License        : MIT
    Repo           : github.com/rack2cloud/Cloud-Cost-Architecture-Review

    Required permissions (read-only, no billing access needed):
      AWS   : ReadOnlyAccess managed policy or equivalent
      Azure : Reader role on target subscription
      GCP   : roles/viewer on target project
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DryRun,
    [string]$AccountId,
    [string]$SubscriptionId,
    [string]$ProjectId,
    [string]$OutputPath = (Get-Location).Path,
    [switch]$AllAccounts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────

$SCHEMA_VERSION  = '1.0.0'
$OUTPUT_FILENAME = 'r2c_topology_payload.json'
$LIFECYCLE_DAYS  = 180

# ─────────────────────────────────────────────────────────────────────────────
# DRY RUN — zero API calls
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-DryRun {
    Write-Host ''
    Write-Host '  ════════════════════════════════════════════════════' -ForegroundColor DarkCyan
    Write-Host '  RACK2CLOUD >_ DRY RUN — COLLECTION SCOPE PREVIEW'    -ForegroundColor Cyan
    Write-Host '  ════════════════════════════════════════════════════' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '  No API calls will be made. This is a schema preview only.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  OUTPUT FILE: r2c_topology_payload.json' -ForegroundColor White
    Write-Host ''
    Write-Host '  FIELDS WRITTEN — TYPE' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '  schema_version                          string'
    Write-Host '  generated_at_utc                        ISO 8601 timestamp'
    Write-Host '  environment_fingerprint                 string (SHA-256 hash, 12-char prefix — no raw identifiers)'
    Write-Host ''
    Write-Host '  environment_shape:' -ForegroundColor White
    Write-Host '    provider_count                        integer'
    Write-Host '    region_count                          integer'
    Write-Host '    account_subscription_count            integer'
    Write-Host '    kubernetes_cluster_count              integer'
    Write-Host '    managed_db_count                      integer'
    Write-Host '    vpc_vnet_count                        integer'
    Write-Host ''
    Write-Host '  ownership_density:' -ForegroundColor White
    Write-Host '    resources_missing_owner_tag_pct       float (percentage)'
    Write-Host '    resources_missing_env_tag_pct         float (percentage)'
    Write-Host '    untagged_resources_over_180d_pct      float (percentage)'
    Write-Host '    unattached_resource_rate_pct          float (percentage)'
    Write-Host ''
    Write-Host '  data_gravity_signals:' -ForegroundColor White
    Write-Host '    inter_region_transfer_enabled         boolean'
    Write-Host '    peering_connection_count              integer'
    Write-Host '    nat_gateway_count                     integer'
    Write-Host '    public_egress_service_count           integer'
    Write-Host '    cdn_usage_present                     boolean'
    Write-Host '    replication_service_present           boolean'
    Write-Host ''
    Write-Host '  control_plane_spread:' -ForegroundColor White
    Write-Host '    cicd_platform_count                   integer'
    Write-Host '    monitoring_stack_count                integer'
    Write-Host '    ingress_controller_count              integer'
    Write-Host '    kubernetes_distro_count               integer'
    Write-Host '    iac_tooling_count                     integer'
    Write-Host ''
    Write-Host '  NEVER COLLECTED:' -ForegroundColor Yellow
    Write-Host '    Billing data, cost exports, invoice line items'
    Write-Host '    Subscription IDs or Tenant IDs (SHA-256 hashed locally, never transmitted)'
    Write-Host '    IP addresses (public or private)'
    Write-Host '    Resource names, display names, or tag values'
    Write-Host '    User principal names or email addresses'
    Write-Host '    Secrets, keys, connection strings, or credentials'
    Write-Host '    Workload payload data of any kind'
    Write-Host '    Savings estimates or optimization recommendations'
    Write-Host ''
    Write-Host '  ════════════════════════════════════════════════════' -ForegroundColor DarkCyan
    Write-Host '  Audit the source code at:'
    Write-Host '  github.com/rack2cloud/Cloud-Cost-Architecture-Review' -ForegroundColor Cyan
    Write-Host '  ════════════════════════════════════════════════════' -ForegroundColor DarkCyan
    Write-Host ''
}

# ─────────────────────────────────────────────────────────────────────────────
# PROVIDER DETECTION
# ─────────────────────────────────────────────────────────────────────────────

function Get-DetectedProviders {
    $providers = @()

    # AWS
    if (Get-Command 'Get-AWSRegion' -ErrorAction SilentlyContinue) {
        try {
            $null = Get-AWSRegion -ErrorAction Stop
            $providers += 'aws'
        } catch { }
    }

    # Azure
    if (Get-Command 'Get-AzContext' -ErrorAction SilentlyContinue) {
        try {
            $ctx = Get-AzContext -ErrorAction Stop
            if ($ctx) { $providers += 'azure' }
        } catch { }
    }

    # GCP
    if (Get-Command 'gcloud' -ErrorAction SilentlyContinue) {
        try {
            $null = & gcloud config get-value project 2>$null
            $providers += 'gcp'
        } catch { }
    }

    return $providers
}

# ─────────────────────────────────────────────────────────────────────────────
# FINGERPRINT — one-way SHA-256, 12-char prefix, no raw identifiers transmitted
# ─────────────────────────────────────────────────────────────────────────────

function Get-EnvironmentFingerprint {
    param([string[]]$Providers)

    $seed = ($Providers -join ',') + [System.DateTime]::UtcNow.ToString('yyyy-MM-dd')
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($seed)
    $hash  = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-','').ToLower().Substring(0, 12)
}

# ─────────────────────────────────────────────────────────────────────────────
# AWS COLLECTION
# ─────────────────────────────────────────────────────────────────────────────

function Get-AWSTopology {
    param([string]$AccountId)

    Write-Host '  [AWS] Collecting topology...' -ForegroundColor Gray

    $shape = @{
        provider_count             = 1
        region_count               = 0
        account_subscription_count = 1
        kubernetes_cluster_count   = 0
        managed_db_count           = 0
        vpc_vnet_count             = 0
    }

    $ownership = @{
        resources_missing_owner_tag_pct      = 0.0
        resources_missing_env_tag_pct        = 0.0
        untagged_resources_over_180d_pct     = 0.0
        unattached_resource_rate_pct         = 0.0
    }

    $gravity = @{
        inter_region_transfer_enabled = $false
        peering_connection_count      = 0
        nat_gateway_count             = 0
        public_egress_service_count   = 0
        cdn_usage_present             = $false
        replication_service_present   = $false
    }

    $control = @{
        cicd_platform_count      = 0
        monitoring_stack_count   = 0
        ingress_controller_count = 0
        kubernetes_distro_count  = 0
        iac_tooling_count        = 0
    }

    try {
        # Regions in use
        $regions = Get-AWSRegion | Where-Object { $_.IsOptInNotRequired -or $_.IsOptIn }
        $activeRegions = @()
        foreach ($r in $regions) {
            try {
                $vpcs = Get-EC2Vpc -Region $r.Region -ErrorAction Stop
                if ($vpcs) { $activeRegions += $r.Region }
            } catch { }
        }
        $shape.region_count = $activeRegions.Count

        # Aggregate across active regions
        $totalResources    = 0
        $missingOwner      = 0
        $missingEnv        = 0
        $oldUntagged       = 0
        $unattached        = 0
        $cutoff            = (Get-Date).AddDays(-$LIFECYCLE_DAYS)

        foreach ($region in $activeRegions) {
            try {
                # VPCs
                $vpcs = Get-EC2Vpc -Region $region -ErrorAction SilentlyContinue
                $shape.vpc_vnet_count += ($vpcs | Measure-Object).Count

                # VPC Peering
                $peering = Get-EC2VpcPeeringConnection -Region $region -ErrorAction SilentlyContinue
                $gravity.peering_connection_count += ($peering | Measure-Object).Count

                # NAT Gateways
                $nats = Get-EC2NatGateway -Region $region -ErrorAction SilentlyContinue
                $gravity.nat_gateway_count += ($nats | Where-Object { $_.State -eq 'available' } | Measure-Object).Count

                # Inter-region transfer — presence of active peering or transit gateway implies it
                if ($peering) { $gravity.inter_region_transfer_enabled = $true }

                # EKS clusters
                $clusters = Get-EKSClusterList -Region $region -ErrorAction SilentlyContinue
                $shape.kubernetes_cluster_count += ($clusters | Measure-Object).Count
                if (($clusters | Measure-Object).Count -gt 0) {
                    $control.kubernetes_distro_count = [Math]::Max($control.kubernetes_distro_count, 1)
                }

                # RDS instances
                $rdbs = Get-RDSDBInstance -Region $region -ErrorAction SilentlyContinue
                $shape.managed_db_count += ($rdbs | Measure-Object).Count

                # EC2 instances — ownership density
                $instances = Get-EC2Instance -Region $region -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty Instances
                foreach ($i in $instances) {
                    $totalResources++
                    $tags = $i.Tags
                    if (-not ($tags | Where-Object { $_.Key -ieq 'owner' }))       { $missingOwner++ }
                    if (-not ($tags | Where-Object { $_.Key -ieq 'environment' -or $_.Key -ieq 'env' })) { $missingEnv++ }
                    # Old untagged — launched before cutoff with no lifecycle tag
                    if ($i.LaunchTime -lt $cutoff -and
                        -not ($tags | Where-Object { $_.Key -ieq 'lifecycle' -or $_.Key -ieq 'expiry' })) {
                        $oldUntagged++
                    }
                }

                # Unattached EBS volumes
                $vols = Get-EC2Volume -Region $region -ErrorAction SilentlyContinue
                $unattachedVols = $vols | Where-Object { $_.State -eq 'available' }
                $unattached   += ($unattachedVols | Measure-Object).Count
                $totalResources += ($vols | Measure-Object).Count

                # Load balancers — public egress proxy
                $lbs = Get-ELB2LoadBalancer -Region $region -ErrorAction SilentlyContinue
                $publicLbs = $lbs | Where-Object { $_.Scheme -eq 'internet-facing' }
                $gravity.public_egress_service_count += ($publicLbs | Measure-Object).Count

                # CloudFront — CDN
                if (-not $gravity.cdn_usage_present) {
                    try {
                        $dists = Get-CFDistributionList -ErrorAction Stop
                        if (($dists | Measure-Object).Count -gt 0) { $gravity.cdn_usage_present = $true }
                    } catch { }
                }

                # S3 replication — replication service presence
                if (-not $gravity.replication_service_present) {
                    try {
                        $buckets = Get-S3Bucket -ErrorAction Stop
                        foreach ($b in $buckets) {
                            try {
                                $rep = Get-S3BucketReplication -BucketName $b.BucketName -ErrorAction Stop
                                if ($rep) { $gravity.replication_service_present = $true; break }
                            } catch { }
                        }
                    } catch { }
                }

                # CodePipeline — CI/CD
                try {
                    $pipes = Get-CPPipelineList -Region $region -ErrorAction Stop
                    if (($pipes | Measure-Object).Count -gt 0) {
                        $control.cicd_platform_count = [Math]::Max($control.cicd_platform_count, 1)
                    }
                } catch { }

                # CloudWatch — monitoring
                try {
                    $alarms = Get-CWAlarm -Region $region -ErrorAction Stop
                    if (($alarms | Measure-Object).Count -gt 0) {
                        $control.monitoring_stack_count = [Math]::Max($control.monitoring_stack_count, 1)
                    }
                } catch { }

            } catch {
                Write-Verbose "  [AWS] Region $region — partial collection: $_"
            }
        }

        # Ownership density percentages
        if ($totalResources -gt 0) {
            $ownership.resources_missing_owner_tag_pct      = [Math]::Round(($missingOwner  / $totalResources) * 100, 1)
            $ownership.resources_missing_env_tag_pct        = [Math]::Round(($missingEnv    / $totalResources) * 100, 1)
            $ownership.untagged_resources_over_180d_pct     = [Math]::Round(($oldUntagged   / $totalResources) * 100, 1)
            $ownership.unattached_resource_rate_pct         = [Math]::Round(($unattached    / $totalResources) * 100, 1)
        }

        # CloudFormation / Terraform detection — IaC tooling
        try {
            $stacks = Get-CFNStack -Region $activeRegions[0] -ErrorAction Stop
            if (($stacks | Measure-Object).Count -gt 0) { $control.iac_tooling_count++ }
        } catch { }

    } catch {
        Write-Warning "  [AWS] Collection error: $_"
    }

    return @{
        shape    = $shape
        ownership = $ownership
        gravity  = $gravity
        control  = $control
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AZURE COLLECTION
# ─────────────────────────────────────────────────────────────────────────────

function Get-AzureTopology {
    param([string]$SubscriptionId)

    Write-Host '  [Azure] Collecting topology...' -ForegroundColor Gray

    if ($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    }

    $shape = @{
        provider_count             = 1
        region_count               = 0
        account_subscription_count = 1
        kubernetes_cluster_count   = 0
        managed_db_count           = 0
        vpc_vnet_count             = 0
    }

    $ownership = @{
        resources_missing_owner_tag_pct      = 0.0
        resources_missing_env_tag_pct        = 0.0
        untagged_resources_over_180d_pct     = 0.0
        unattached_resource_rate_pct         = 0.0
    }

    $gravity = @{
        inter_region_transfer_enabled = $false
        peering_connection_count      = 0
        nat_gateway_count             = 0
        public_egress_service_count   = 0
        cdn_usage_present             = $false
        replication_service_present   = $false
    }

    $control = @{
        cicd_platform_count      = 0
        monitoring_stack_count   = 0
        ingress_controller_count = 0
        kubernetes_distro_count  = 0
        iac_tooling_count        = 0
    }

    try {
        # All resources in subscription
        $allResources = Get-AzResource -ErrorAction Stop
        $totalResources = ($allResources | Measure-Object).Count
        $cutoff = (Get-Date).AddDays(-$LIFECYCLE_DAYS)

        $missingOwner  = 0
        $missingEnv    = 0
        $oldUntagged   = 0

        foreach ($r in $allResources) {
            $tags = $r.Tags
            if (-not $tags -or -not $tags.ContainsKey('owner'))                    { $missingOwner++ }
            if (-not $tags -or (-not $tags.ContainsKey('environment') -and
                                -not $tags.ContainsKey('env')))                    { $missingEnv++ }
            # CreatedTime not always available on Get-AzResource — use ChangedTime as proxy
            if ($r.ChangedTime -and $r.ChangedTime -lt $cutoff -and
                (-not $tags -or (-not $tags.ContainsKey('lifecycle') -and
                                 -not $tags.ContainsKey('expiry'))))               { $oldUntagged++ }
        }

        if ($totalResources -gt 0) {
            $ownership.resources_missing_owner_tag_pct  = [Math]::Round(($missingOwner / $totalResources) * 100, 1)
            $ownership.resources_missing_env_tag_pct    = [Math]::Round(($missingEnv   / $totalResources) * 100, 1)
            $ownership.untagged_resources_over_180d_pct = [Math]::Round(($oldUntagged  / $totalResources) * 100, 1)
        }

        # VNets
        $vnets = Get-AzVirtualNetwork -ErrorAction SilentlyContinue
        $shape.vpc_vnet_count = ($vnets | Measure-Object).Count

        # Active regions
        $shape.region_count = ($allResources | Select-Object -ExpandProperty Location -Unique | Measure-Object).Count

        # VNet Peering
        foreach ($vnet in $vnets) {
            $peerings = Get-AzVirtualNetworkPeering -VirtualNetworkName $vnet.Name -ResourceGroupName $vnet.ResourceGroupName -ErrorAction SilentlyContinue
            $gravity.peering_connection_count += ($peerings | Measure-Object).Count
            if (($peerings | Measure-Object).Count -gt 0) { $gravity.inter_region_transfer_enabled = $true }
        }

        # NAT Gateways
        $nats = Get-AzNatGateway -ErrorAction SilentlyContinue
        $gravity.nat_gateway_count = ($nats | Measure-Object).Count

        # AKS clusters
        $aks = Get-AzAksCluster -ErrorAction SilentlyContinue
        $shape.kubernetes_cluster_count = ($aks | Measure-Object).Count
        if ($shape.kubernetes_cluster_count -gt 0) { $control.kubernetes_distro_count = 1 }

        # Managed databases — SQL, PostgreSQL, MySQL, CosmosDB
        $sqlServers  = Get-AzSqlServer -ErrorAction SilentlyContinue
        $pgServers   = Get-AzResource -ResourceType 'Microsoft.DBforPostgreSQL/servers' -ErrorAction SilentlyContinue
        $myServers   = Get-AzResource -ResourceType 'Microsoft.DBforMySQL/servers' -ErrorAction SilentlyContinue
        $cosmosAccts = Get-AzCosmosDBAccount -ErrorAction SilentlyContinue
        $shape.managed_db_count = ($sqlServers | Measure-Object).Count +
                                   ($pgServers  | Measure-Object).Count +
                                   ($myServers  | Measure-Object).Count +
                                   ($cosmosAccts | Measure-Object).Count

        # Public load balancers — egress
        $lbs = Get-AzLoadBalancer -ErrorAction SilentlyContinue
        $gravity.public_egress_service_count = ($lbs | Where-Object { $_.FrontendIpConfigurations.PublicIpAddress } | Measure-Object).Count

        # CDN profiles
        $cdn = Get-AzResource -ResourceType 'Microsoft.Cdn/profiles' -ErrorAction SilentlyContinue
        $gravity.cdn_usage_present = (($cdn | Measure-Object).Count -gt 0)

        # Storage replication — GRS/RAGRS accounts indicate cross-region replication
        $storage = Get-AzStorageAccount -ErrorAction SilentlyContinue
        $replicated = $storage | Where-Object { $_.Sku.Name -match 'GRS|RAGRS|GZRS' }
        $gravity.replication_service_present = (($replicated | Measure-Object).Count -gt 0)

        # Unattached managed disks
        $disks = Get-AzDisk -ErrorAction SilentlyContinue
        $unattached = ($disks | Where-Object { $_.DiskState -eq 'Unattached' } | Measure-Object).Count
        if ($totalResources -gt 0) {
            $ownership.unattached_resource_rate_pct = [Math]::Round(($unattached / $totalResources) * 100, 1)
        }

        # Monitoring — Log Analytics workspaces / Azure Monitor
        $workspaces = Get-AzOperationalInsightsWorkspace -ErrorAction SilentlyContinue
        if (($workspaces | Measure-Object).Count -gt 0) { $control.monitoring_stack_count++ }

        # IaC — ARM deployments presence
        $rgs = Get-AzResourceGroup -ErrorAction SilentlyContinue
        foreach ($rg in $rgs | Select-Object -First 5) {
            $deployments = Get-AzResourceGroupDeployment -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
            if (($deployments | Measure-Object).Count -gt 0) {
                $control.iac_tooling_count = [Math]::Max($control.iac_tooling_count, 1)
                break
            }
        }

        # Azure DevOps presence is external — flag as 0 (cannot be detected via Az module)
        # CI/CD: check for Logic Apps or Function Apps as proxy signals
        $funcApps = Get-AzResource -ResourceType 'Microsoft.Web/sites' -ErrorAction SilentlyContinue |
            Where-Object { $_.Kind -match 'functionapp' }
        if (($funcApps | Measure-Object).Count -gt 0) { $control.cicd_platform_count = 1 }

        # Ingress — Application Gateways
        $appGws = Get-AzApplicationGateway -ErrorAction SilentlyContinue
        $control.ingress_controller_count = ($appGws | Measure-Object).Count

    } catch {
        Write-Warning "  [Azure] Collection error: $_"
    }

    return @{
        shape    = $shape
        ownership = $ownership
        gravity  = $gravity
        control  = $control
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# GCP COLLECTION
# ─────────────────────────────────────────────────────────────────────────────

function Get-GCPTopology {
    param([string]$ProjectId)

    Write-Host '  [GCP] Collecting topology...' -ForegroundColor Gray

    if (-not $ProjectId) {
        $ProjectId = (& gcloud config get-value project 2>$null).Trim()
    }

    if (-not $ProjectId) {
        Write-Warning '  [GCP] No project ID detected. Set default project with: gcloud config set project PROJECT_ID'
        return $null
    }

    $shape = @{
        provider_count             = 1
        region_count               = 0
        account_subscription_count = 1
        kubernetes_cluster_count   = 0
        managed_db_count           = 0
        vpc_vnet_count             = 0
    }

    $ownership = @{
        resources_missing_owner_tag_pct      = 0.0
        resources_missing_env_tag_pct        = 0.0
        untagged_resources_over_180d_pct     = 0.0
        unattached_resource_rate_pct         = 0.0
    }

    $gravity = @{
        inter_region_transfer_enabled = $false
        peering_connection_count      = 0
        nat_gateway_count             = 0
        public_egress_service_count   = 0
        cdn_usage_present             = $false
        replication_service_present   = $false
    }

    $control = @{
        cicd_platform_count      = 0
        monitoring_stack_count   = 0
        ingress_controller_count = 0
        kubernetes_distro_count  = 0
        iac_tooling_count        = 0
    }

    try {
        # VPCs (GCP: networks)
        $networks = (& gcloud compute networks list --project=$ProjectId --format=json 2>$null | ConvertFrom-Json)
        $shape.vpc_vnet_count = ($networks | Measure-Object).Count

        # VPC Peering
        foreach ($net in $networks) {
            $peerings = $net.peerings
            if ($peerings) {
                $gravity.peering_connection_count += ($peerings | Measure-Object).Count
                $gravity.inter_region_transfer_enabled = $true
            }
        }

        # Active regions — from instances
        $instances = (& gcloud compute instances list --project=$ProjectId --format=json 2>$null | ConvertFrom-Json)
        $activeRegions = $instances | ForEach-Object {
            $_.zone -replace '-[a-z]$', ''  # strip zone suffix to get region
        } | Sort-Object -Unique
        $shape.region_count = ($activeRegions | Measure-Object).Count

        # Ownership density — GCP labels as tags proxy
        $totalResources = ($instances | Measure-Object).Count
        $missingOwner = 0
        $missingEnv   = 0
        $oldUntagged  = 0
        $cutoff       = (Get-Date).AddDays(-$LIFECYCLE_DAYS)

        foreach ($i in $instances) {
            $labels = $i.labels
            if (-not $labels -or -not $labels.PSObject.Properties['owner'])          { $missingOwner++ }
            if (-not $labels -or (-not $labels.PSObject.Properties['environment'] -and
                                  -not $labels.PSObject.Properties['env']))           { $missingEnv++ }
            $created = [datetime]::Parse($i.creationTimestamp)
            if ($created -lt $cutoff -and
                (-not $labels -or -not $labels.PSObject.Properties['lifecycle']))     { $oldUntagged++ }
        }

        # Unattached disks
        $disks = (& gcloud compute disks list --project=$ProjectId --format=json 2>$null | ConvertFrom-Json)
        $unattached = ($disks | Where-Object { -not $_.users } | Measure-Object).Count
        $totalResources += ($disks | Measure-Object).Count

        if ($totalResources -gt 0) {
            $ownership.resources_missing_owner_tag_pct      = [Math]::Round(($missingOwner / $totalResources) * 100, 1)
            $ownership.resources_missing_env_tag_pct        = [Math]::Round(($missingEnv   / $totalResources) * 100, 1)
            $ownership.untagged_resources_over_180d_pct     = [Math]::Round(($oldUntagged  / $totalResources) * 100, 1)
            $ownership.unattached_resource_rate_pct         = [Math]::Round(($unattached   / $totalResources) * 100, 1)
        }

        # NAT gateways (GCP: Cloud NAT via routers)
        $routers = (& gcloud compute routers list --project=$ProjectId --format=json 2>$null | ConvertFrom-Json)
        foreach ($router in $routers) {
            $nats = (& gcloud compute routers nats list --router=$($router.name) --region=$($router.region.Split('/')[-1]) --project=$ProjectId --format=json 2>$null | ConvertFrom-Json)
            $gravity.nat_gateway_count += ($nats | Measure-Object).Count
        }

        # GKE clusters
        $clusters = (& gcloud container clusters list --project=$ProjectId --format=json 2>$null | ConvertFrom-Json)
        $shape.kubernetes_cluster_count = ($clusters | Measure-Object).Count
        if ($shape.kubernetes_cluster_count -gt 0) { $control.kubernetes_distro_count = 1 }

        # Cloud SQL
        $sqlInstances = (& gcloud sql instances list --project=$ProjectId --format=json 2>$null | ConvertFrom-Json)
        $shape.managed_db_count = ($sqlInstances | Measure-Object).Count

        # Public forwarding rules — egress
        $fwdRules = (& gcloud compute forwarding-rules list --project=$ProjectId --format=json 2>$null | ConvertFrom-Json)
        $gravity.public_egress_service_count = ($fwdRules | Where-Object { $_.loadBalancingScheme -eq 'EXTERNAL' } | Measure-Object).Count

        # CDN — backend services with CDN enabled
        $backends = (& gcloud compute backend-services list --project=$ProjectId --format=json 2>$null | ConvertFrom-Json)
        $gravity.cdn_usage_present = (($backends | Where-Object { $_.enableCDN } | Measure-Object).Count -gt 0)

        # Replication — Cloud Storage multi-region or dual-region buckets
        $buckets = (& gcloud storage buckets list --project=$ProjectId --format=json 2>$null | ConvertFrom-Json)
        $replicated = $buckets | Where-Object { $_.location_type -match 'multi-region|dual-region' }
        $gravity.replication_service_present = (($replicated | Measure-Object).Count -gt 0)

        # Cloud Monitoring
        $alertPolicies = (& gcloud alpha monitoring policies list --project=$ProjectId --format=json 2>$null | ConvertFrom-Json)
        if (($alertPolicies | Measure-Object).Count -gt 0) { $control.monitoring_stack_count = 1 }

        # Cloud Build — CI/CD
        $builds = (& gcloud builds list --project=$ProjectId --limit=1 --format=json 2>$null | ConvertFrom-Json)
        if (($builds | Measure-Object).Count -gt 0) { $control.cicd_platform_count = 1 }

        # Deployment Manager — IaC
        $deployments = (& gcloud deployment-manager deployments list --project=$ProjectId --format=json 2>$null | ConvertFrom-Json)
        if (($deployments | Measure-Object).Count -gt 0) { $control.iac_tooling_count = 1 }

        # Ingress — from GKE ingress resources (requires kubectl context)
        if (Get-Command kubectl -ErrorAction SilentlyContinue) {
            try {
                $ingresses = (& kubectl get ingress --all-namespaces -o json 2>$null | ConvertFrom-Json)
                $control.ingress_controller_count = ($ingresses.items | Measure-Object).Count
            } catch { }
        }

    } catch {
        Write-Warning "  [GCP] Collection error: $_"
    }

    return @{
        shape    = $shape
        ownership = $ownership
        gravity  = $gravity
        control  = $control
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# MERGE MULTI-PROVIDER RESULTS
# ─────────────────────────────────────────────────────────────────────────────

function Merge-TopologyResults {
    param([hashtable[]]$Results)

    $merged = @{
        shape = @{
            provider_count             = ($Results | Measure-Object).Count
            region_count               = 0
            account_subscription_count = 0
            kubernetes_cluster_count   = 0
            managed_db_count           = 0
            vpc_vnet_count             = 0
        }
        ownership = @{
            resources_missing_owner_tag_pct      = 0.0
            resources_missing_env_tag_pct        = 0.0
            untagged_resources_over_180d_pct     = 0.0
            unattached_resource_rate_pct         = 0.0
        }
        gravity = @{
            inter_region_transfer_enabled = $false
            peering_connection_count      = 0
            nat_gateway_count             = 0
            public_egress_service_count   = 0
            cdn_usage_present             = $false
            replication_service_present   = $false
        }
        control = @{
            cicd_platform_count      = 0
            monitoring_stack_count   = 0
            ingress_controller_count = 0
            kubernetes_distro_count  = 0
            iac_tooling_count        = 0
        }
    }

    $ownershipValues = @{ owner = @(); env = @(); old = @(); unattached = @() }

    foreach ($r in $Results) {
        $merged.shape.region_count               += $r.shape.region_count
        $merged.shape.account_subscription_count += $r.shape.account_subscription_count
        $merged.shape.kubernetes_cluster_count   += $r.shape.kubernetes_cluster_count
        $merged.shape.managed_db_count           += $r.shape.managed_db_count
        $merged.shape.vpc_vnet_count             += $r.shape.vpc_vnet_count

        $ownershipValues.owner     += $r.ownership.resources_missing_owner_tag_pct
        $ownershipValues.env       += $r.ownership.resources_missing_env_tag_pct
        $ownershipValues.old       += $r.ownership.untagged_resources_over_180d_pct
        $ownershipValues.unattached += $r.ownership.unattached_resource_rate_pct

        if ($r.gravity.inter_region_transfer_enabled)  { $merged.gravity.inter_region_transfer_enabled = $true }
        $merged.gravity.peering_connection_count      += $r.gravity.peering_connection_count
        $merged.gravity.nat_gateway_count             += $r.gravity.nat_gateway_count
        $merged.gravity.public_egress_service_count   += $r.gravity.public_egress_service_count
        if ($r.gravity.cdn_usage_present)              { $merged.gravity.cdn_usage_present = $true }
        if ($r.gravity.replication_service_present)    { $merged.gravity.replication_service_present = $true }

        $merged.control.cicd_platform_count      += $r.control.cicd_platform_count
        $merged.control.monitoring_stack_count   += $r.control.monitoring_stack_count
        $merged.control.ingress_controller_count += $r.control.ingress_controller_count
        $merged.control.kubernetes_distro_count  += $r.control.kubernetes_distro_count
        $merged.control.iac_tooling_count        += $r.control.iac_tooling_count
    }

    # Average ownership density across providers
    $n = ($Results | Measure-Object).Count
    if ($n -gt 0) {
        $merged.ownership.resources_missing_owner_tag_pct      = [Math]::Round(($ownershipValues.owner      | Measure-Object -Average).Average, 1)
        $merged.ownership.resources_missing_env_tag_pct        = [Math]::Round(($ownershipValues.env        | Measure-Object -Average).Average, 1)
        $merged.ownership.untagged_resources_over_180d_pct     = [Math]::Round(($ownershipValues.old        | Measure-Object -Average).Average, 1)
        $merged.ownership.unattached_resource_rate_pct         = [Math]::Round(($ownershipValues.unattached | Measure-Object -Average).Average, 1)
    }

    return $merged
}

# ─────────────────────────────────────────────────────────────────────────────
# CONSOLE SUMMARY OUTPUT
# ─────────────────────────────────────────────────────────────────────────────

function Write-TopologySummary {
    param([hashtable]$Topology, [string]$OutputFile)

    $s = $Topology.shape
    $o = $Topology.ownership
    $g = $Topology.gravity
    $c = $Topology.control

    Write-Host ''
    Write-Host '  ════════════════════════════════════════════════════' -ForegroundColor DarkCyan
    Write-Host '  RACK2CLOUD >_ COST TOPOLOGY COLLECTION — COMPLETE'   -ForegroundColor Cyan
    Write-Host '  ════════════════════════════════════════════════════' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '  ENVIRONMENT SHAPE:' -ForegroundColor White
    Write-Host ("    Providers detected:         {0}" -f $s.provider_count)
    Write-Host ("    Regions in use:             {0}" -f $s.region_count)
    Write-Host ("    Accounts / Subscriptions:   {0}" -f $s.account_subscription_count)
    Write-Host ("    Kubernetes clusters:        {0}" -f $s.kubernetes_cluster_count)
    Write-Host ("    Managed databases:          {0}" -f $s.managed_db_count)
    Write-Host ("    VPCs / VNets:               {0}" -f $s.vpc_vnet_count)
    Write-Host ''
    Write-Host '  OWNERSHIP DENSITY:' -ForegroundColor White
    Write-Host ("    Resources missing owner tag:      {0}%" -f $o.resources_missing_owner_tag_pct)
    Write-Host ("    Resources missing env tag:        {0}%" -f $o.resources_missing_env_tag_pct)
    Write-Host ("    Untagged resources >180 days:     {0}%" -f $o.untagged_resources_over_180d_pct)
    Write-Host ("    Unattached resource rate:         {0}%" -f $o.unattached_resource_rate_pct)
    Write-Host ''
    Write-Host '  DATA GRAVITY SIGNALS:' -ForegroundColor White
    Write-Host ("    Inter-region transfer:    {0}"  -f $(if ($g.inter_region_transfer_enabled) { 'ENABLED' } else { 'NOT DETECTED' }))
    Write-Host ("    Peering connections:      {0}"  -f $g.peering_connection_count)
    Write-Host ("    NAT gateways:             {0}"  -f $g.nat_gateway_count)
    Write-Host ("    Public egress services:   {0}"  -f $g.public_egress_service_count)
    Write-Host ("    CDN coverage:             {0}"  -f $(if ($g.cdn_usage_present) { 'DETECTED' } else { 'NOT DETECTED' }))
    Write-Host ("    Replication services:     {0}"  -f $(if ($g.replication_service_present) { 'DETECTED' } else { 'NOT DETECTED' }))
    Write-Host ''
    Write-Host '  CONTROL PLANE SPREAD:' -ForegroundColor White
    Write-Host ("    CI/CD platforms:          {0}" -f $c.cicd_platform_count)
    Write-Host ("    Monitoring stacks:        {0}" -f $c.monitoring_stack_count)
    Write-Host ("    Ingress controllers:      {0}" -f $c.ingress_controller_count)
    Write-Host ("    Kubernetes distros:       {0}" -f $c.kubernetes_distro_count)
    Write-Host ("    IaC tooling:              {0}" -f $c.iac_tooling_count)
    Write-Host ''
    Write-Host '  ────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ("  Payload written: {0}" -f $OutputFile) -ForegroundColor Green
    Write-Host '  Review the file before uploading.'
    Write-Host ''
    Write-Host '  NEXT STEP:' -ForegroundColor White
    Write-Host '  Include r2c_topology_payload.json with your intake at:'
    Write-Host '  rack2cloud.com/audits/cost-architecture-review/' -ForegroundColor Cyan
    Write-Host '  ════════════════════════════════════════════════════' -ForegroundColor DarkCyan
    Write-Host ''
}

# ─────────────────────────────────────────────────────────────────────────────
# BUILD JSON PAYLOAD
# ─────────────────────────────────────────────────────────────────────────────

function Build-Payload {
    param([hashtable]$Topology, [string]$Fingerprint)

    return [ordered]@{
        schema_version          = $SCHEMA_VERSION
        generated_at_utc        = [System.DateTime]::UtcNow.ToString('o')
        environment_fingerprint = $Fingerprint
        environment_shape       = [ordered]@{
            provider_count             = $Topology.shape.provider_count
            region_count               = $Topology.shape.region_count
            account_subscription_count = $Topology.shape.account_subscription_count
            kubernetes_cluster_count   = $Topology.shape.kubernetes_cluster_count
            managed_db_count           = $Topology.shape.managed_db_count
            vpc_vnet_count             = $Topology.shape.vpc_vnet_count
        }
        ownership_density       = [ordered]@{
            resources_missing_owner_tag_pct      = $Topology.ownership.resources_missing_owner_tag_pct
            resources_missing_env_tag_pct        = $Topology.ownership.resources_missing_env_tag_pct
            untagged_resources_over_180d_pct     = $Topology.ownership.untagged_resources_over_180d_pct
            unattached_resource_rate_pct         = $Topology.ownership.unattached_resource_rate_pct
        }
        data_gravity_signals    = [ordered]@{
            inter_region_transfer_enabled = $Topology.gravity.inter_region_transfer_enabled
            peering_connection_count      = $Topology.gravity.peering_connection_count
            nat_gateway_count             = $Topology.gravity.nat_gateway_count
            public_egress_service_count   = $Topology.gravity.public_egress_service_count
            cdn_usage_present             = $Topology.gravity.cdn_usage_present
            replication_service_present   = $Topology.gravity.replication_service_present
        }
        control_plane_spread    = [ordered]@{
            cicd_platform_count      = $Topology.control.cicd_platform_count
            monitoring_stack_count   = $Topology.control.monitoring_stack_count
            ingress_controller_count = $Topology.control.ingress_controller_count
            kubernetes_distro_count  = $Topology.control.kubernetes_distro_count
            iac_tooling_count        = $Topology.control.iac_tooling_count
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

if ($DryRun) {
    Invoke-DryRun
    exit 0
}

Write-Host ''
Write-Host '  RACK2CLOUD >_ COST TOPOLOGY COLLECTION — STARTING' -ForegroundColor Cyan
Write-Host '  Collecting structural metadata only. No billing data.' -ForegroundColor Gray
Write-Host ''

$providers  = Get-DetectedProviders
$results    = @()

if ($providers.Count -eq 0) {
    Write-Error 'No authenticated cloud provider context detected. Authenticate with AWS, Azure, or GCP before running.'
    exit 1
}

Write-Host ("  Providers detected: {0}" -f ($providers -join ', ')) -ForegroundColor Gray
Write-Host ''

foreach ($provider in $providers) {
    switch ($provider) {
        'aws'   { $results += Get-AWSTopology   -AccountId      $AccountId }
        'azure' { $results += Get-AzureTopology -SubscriptionId $SubscriptionId }
        'gcp'   { $r = Get-GCPTopology -ProjectId $ProjectId; if ($r) { $results += $r } }
    }
}

if ($results.Count -eq 0) {
    Write-Error 'No topology data collected. Check provider authentication and permissions.'
    exit 1
}

$merged      = if ($results.Count -gt 1) { Merge-TopologyResults -Results $results } else { $results[0] }
$merged.shape.provider_count = $providers.Count

$fingerprint = Get-EnvironmentFingerprint -Providers $providers
$payload     = Build-Payload -Topology $merged -Fingerprint $fingerprint

# Write output
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$outputFile = Join-Path $OutputPath $OUTPUT_FILENAME
$payload | ConvertTo-Json -Depth 5 | Set-Content -Path $outputFile -Encoding UTF8

Write-TopologySummary -Topology $merged -OutputFile $outputFile