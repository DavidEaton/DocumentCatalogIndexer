[CmdletBinding()]
param(
    [string]$ConfigPath = $(Join-Path $PSScriptRoot "documentcatalog-backfiller-azure.config.json"),
    [string]$ImageTag,
    [switch]$SkipBuild,
    [switch]$BuildOnly,
    [switch]$StartJob,
    [ValidateSet("CII", "CSI", "DSI", "DSN")]
    [string]$Company,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Prevent PowerShell 7 from turning stderr into terminating errors
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $false
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Configuration file not found: $ConfigPath"
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$SubscriptionId = $Config.SubscriptionId
$AzureCliPath = if ([string]::IsNullOrWhiteSpace($Config.AzureCliPath)) { "az" } else { $Config.AzureCliPath }

$ResourceGroupName = $Config.ResourceGroup.Name
$ResourceGroupLocation = $Config.ResourceGroup.Location
$ContainerRegistryName = $Config.ContainerRegistry.Name
$ContainerRegistrySku = $Config.ContainerRegistry.Sku
$RepositoryName = $Config.ContainerImage.RepositoryName
$DockerfilePath = Join-Path $repoRoot $Config.ContainerImage.DockerfilePath
$ContainerAppsEnvironmentName = $Config.ContainerApps.EnvironmentName
$JobName = $Config.ContainerApps.JobName
$Cpu = $Config.ContainerApps.Cpu
$Memory = $Config.ContainerApps.Memory
$ReplicaTimeout = $Config.ContainerApps.ReplicaTimeout
$ReplicaRetryLimit = $Config.ContainerApps.ReplicaRetryLimit
$Parallelism = $Config.ContainerApps.Parallelism
$ReplicaCompletionCount = $Config.ContainerApps.ReplicaCompletionCount
$SqlServerName = $Config.Sql.ServerName
$SqlDatabases = $Config.Sql.Databases
$StorageAccounts = @($Config.StorageAccounts)

if ([string]::IsNullOrWhiteSpace($ImageTag)) {
    $ImageTag = (Get-Date).ToUniversalTime().ToString("yyyy.MM.dd.HHmmss")
}

$VersionedImage = "$RepositoryName`:$ImageTag"
$LatestImage = "$RepositoryName`:latest"
$FullyQualifiedImage = "$ContainerRegistryName.azurecr.io/$RepositoryName`:$ImageTag"

function Invoke-Az {
    param(
        [switch]$AllowFailure,
        [switch]$StreamOutput,
        [switch]$AllowNonJsonOutput,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $effectiveArguments = $Arguments + @('--only-show-errors')
    $commandText = "az $($effectiveArguments -join ' ')"
    Write-Host $commandText -ForegroundColor DarkGray

    $previousErrorActionPreference = $ErrorActionPreference
    $previousNativeErrorPreference = $null

    if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
        $previousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
        $global:PSNativeCommandUseErrorActionPreference = $false
    }

    try {
        $ErrorActionPreference = "Continue"

        if ($StreamOutput) {
            & $AzureCliPath @effectiveArguments 2>&1 | ForEach-Object {
                Write-Host $_
            }

            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0 -and -not $AllowFailure) {
                throw ("Azure CLI command failed with exit code {0}: {1}" -f `
                        $exitCode,
                    $commandText)
            }

            return [pscustomobject]@{
                ExitCode = $exitCode
                Output   = @()
            }
        }

        try {
            $output = & $AzureCliPath @effectiveArguments 2>&1
            $exitCode = $LASTEXITCODE
        }
        catch {
            $output = $_ | Out-String
            $exitCode = $LASTEXITCODE

            # If exit code is 0, ignore this fake error
            if ($exitCode -eq 0) {
                Write-Host "(Ignored spurious PowerShell NativeCommandError)" -ForegroundColor DarkYellow
            }
            else {
                throw
            }
        }
        
        $outputText = ($output | Out-String).Trim()

        if (-not [string]::IsNullOrWhiteSpace($outputText)) {
            Write-Host $outputText
        }

        if ($exitCode -eq 0) {
            return [pscustomobject]@{
                ExitCode = $exitCode
                Output   = $output
            }
        }

        if ($AllowFailure) {
            return [pscustomobject]@{
                ExitCode = $exitCode
                Output   = $output
            }
        }

        throw ("Azure CLI command failed with exit code {0}: {1}`n{2}" -f `
                $exitCode,
            $commandText,
            $outputText)
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference

        if ($null -ne $previousNativeErrorPreference) {
            $global:PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
        }
    }
}

function Get-TextValue {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $result = Invoke-Az -AllowNonJsonOutput @Arguments
    $text = ($result.Output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text
}

function Test-JobExists {
    $result = Invoke-Az -AllowFailure -AllowNonJsonOutput containerapp job show --name $JobName --resource-group $ResourceGroupName --output none
    return $result.ExitCode -eq 0
}

function Ensure-RoleAssignment {
    param(
        [Parameter(Mandatory)] [string]$PrincipalId,
        [Parameter(Mandatory)] [string]$RoleName,
        [Parameter(Mandatory)] [string]$Scope
    )

    $existing = Get-TextValue role assignment list `
        --assignee-object-id $PrincipalId `
        --role $RoleName `
        --scope $Scope `
        --query "[0].id" `
        --output tsv

    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        return
    }

    Invoke-Az role assignment create `
        --assignee-object-id $PrincipalId `
        --assignee-principal-type ServicePrincipal `
        --role $RoleName `
        --scope $Scope | Out-Null
}

Write-Host "Using config: $ConfigPath"
Write-Host "Image tag: $ImageTag"

Invoke-Az -AllowNonJsonOutput account set --subscription $SubscriptionId | Out-Null
Invoke-Az account show --query "{name:name, id:id}" --output json | Out-Null

Invoke-Az provider register --namespace Microsoft.App | Out-Null
Invoke-Az provider register --namespace Microsoft.OperationalInsights | Out-Null

Invoke-Az group create --name $ResourceGroupName --location $ResourceGroupLocation | Out-Null
Invoke-Az acr create --resource-group $ResourceGroupName --name $ContainerRegistryName --sku $ContainerRegistrySku --admin-enabled false | Out-Null

if (-not $SkipBuild) {
    Push-Location $repoRoot
    try {
        Invoke-Az -StreamOutput acr build `
            --registry $ContainerRegistryName `
            --image $VersionedImage `
            --image $LatestImage `
            --file $DockerfilePath `
            . | Out-Null
    }
    finally {
        Pop-Location
    }
}

if ($BuildOnly) { return }

# Ensure Container Apps Environment
$envExists = (Invoke-Az -AllowFailure -AllowNonJsonOutput `
        containerapp env show `
        --name $ContainerAppsEnvironmentName `
        --resource-group $ResourceGroupName `
        --output none).ExitCode -eq 0

if (-not $envExists) {
    Invoke-Az containerapp env create `
        --name $ContainerAppsEnvironmentName `
        --resource-group $ResourceGroupName `
        --location $ResourceGroupLocation | Out-Null
}

# =========================
# Ensure Job Exists
# =========================
$envVars = @(
    "SQL_SERVER=$SqlServerName",
    "CII_SQL_DATABASE=$($SqlDatabases.CII)",
    "CSI_SQL_DATABASE=$($SqlDatabases.CSI)",
    "DSI_SQL_DATABASE=$($SqlDatabases.DSI)",
    "DSN_SQL_DATABASE=$($SqlDatabases.DSN)",
    "COMPANY=",
    "DRY_RUN=TRUE",
    "BUILD_MARKER=$ImageTag",
    "BACKFILL_LOG_PATH=/mnt/backfiller-logs/documentcatalog/backfiller/log-.txt"
)

foreach ($storageAccount in $StorageAccounts) {
    $envVars += "$($storageAccount.Code)_BLOB_ACCOUNT_URL=$($storageAccount.BlobAccountUrl)"
}

$jobExists = Test-JobExists

if (-not $jobExists) {
    Write-Host "Creating Container Apps job..." -ForegroundColor Cyan
    Invoke-Az -StreamOutput containerapp job create `
        --name $JobName `
        --resource-group $ResourceGroupName `
        --environment $ContainerAppsEnvironmentName `
        --trigger-type Manual `
        --replica-timeout $ReplicaTimeout `
        --replica-retry-limit $ReplicaRetryLimit `
        --replica-completion-count $ReplicaCompletionCount `
        --parallelism $Parallelism `
        --image $FullyQualifiedImage `
        --cpu $Cpu `
        --memory $Memory `
        --env-vars @envVars | Out-Null
}
else {
    Write-Host "Updating existing Container Apps job..." -ForegroundColor Cyan

    Invoke-Az containerapp job update `
        --name $JobName `
        --resource-group $ResourceGroupName `
        --image $FullyQualifiedImage `
        --cpu $Cpu `
        --memory $Memory `
        --set-env-vars @envVars | Out-Null
}

# =========================
# Ensure Managed Identity
# =========================
Invoke-Az containerapp job identity assign `
    --name $JobName `
    --resource-group $ResourceGroupName `
    --system-assigned | Out-Null

# Get principal ID
$principalId = Get-TextValue containerapp job identity show `
    --name $JobName `
    --resource-group $ResourceGroupName `
    --query principalId `
    --output tsv

if ([string]::IsNullOrWhiteSpace($principalId)) {
    throw "Failed to retrieve managed identity principalId."
}

# =========================
# Ensure ACR Pull Role
# =========================
$acrId = Get-TextValue acr show `
    --name $ContainerRegistryName `
    --resource-group $ResourceGroupName `
    --query id `
    --output tsv

Ensure-RoleAssignment `
    -PrincipalId $principalId `
    -RoleName "AcrPull" `
    -Scope $acrId

# =========================
# Ensure Blob Roles
# =========================
foreach ($storageAccount in $StorageAccounts) {
    $storageId = Get-TextValue storage account show `
        --name $storageAccount.Name `
        --resource-group $storageAccount.ResourceGroupName `
        --query id `
        --output tsv

    Ensure-RoleAssignment `
        -PrincipalId $principalId `
        -RoleName "Storage Blob Data Reader" `
        -Scope $storageId
}

# =========================
# Configure Registry (Managed Identity)
# =========================
Invoke-Az containerapp job registry set `
    --name $JobName `
    --resource-group $ResourceGroupName `
    --server "$ContainerRegistryName.azurecr.io" `
    --identity system | Out-Null

Write-Host "Refreshing job template after identity and registry configuration..." -ForegroundColor Cyan

Invoke-Az containerapp job update `
    --name $JobName `
    --resource-group $ResourceGroupName `
    --image $FullyQualifiedImage `
    --cpu $Cpu `
    --memory $Memory `
    --set-env-vars @envVars | Out-Null
    
# =========================
# Start Job (optional)
# =========================
if ($StartJob) {
    $args = @()

    if ($Company) {
        $args += "--company"
        $args += $Company
    }

    if ($DryRun) {
        $args += "--dry-run"
    }

    Invoke-Az -StreamOutput containerapp job start `
        --name $JobName `
        --resource-group $ResourceGroupName `
        --args $args | Out-Null
}

Write-Host ""
Write-Host "Deployment complete." -ForegroundColor Green