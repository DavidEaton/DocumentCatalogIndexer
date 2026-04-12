[CmdletBinding()]
param(
    [string]$ConfigPath = ".\provision-documentcatalog-backfiller-azure.config.json",
    [switch]$NonInteractive,
    [string]$StartAt = "SetSubscription",
    [string]$StopAfter
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# LOAD CONFIGURATION
# =========================
if (-not (Test-Path $ConfigPath)) {
    throw "Configuration file not found: $ConfigPath"
}

$Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

$SubscriptionId = $Config.SubscriptionId
$AzureCliPath = $Config.AzureCliPath

$PrimaryResourceGroupName = $Config.ResourceGroup.Name
$PrimaryResourceGroupLocation = $Config.ResourceGroup.Location

$ContainerRegistryName = $Config.ContainerRegistry.Name
$ContainerRegistrySku = $Config.ContainerRegistry.Sku

$ContainerImageRepositoryName = $Config.ContainerImage.RepositoryName
$ContainerImageTag = $Config.ContainerImage.Tag
$DockerfilePath = $Config.ContainerImage.DockerfilePath

$VersionedContainerImageName = "${ContainerImageRepositoryName}:${ContainerImageTag}"
$LatestContainerImageName = "${ContainerImageRepositoryName}:latest"
$FullyQualifiedContainerImageName = "${ContainerRegistryName}.azurecr.io/${ContainerImageRepositoryName}:${ContainerImageTag}"

$ContainerAppsEnvironmentName = $Config.ContainerApps.EnvironmentName
$ContainerAppsJobName = $Config.ContainerApps.JobName
$ContainerAppsJobCpu = $Config.ContainerApps.Cpu
$ContainerAppsJobMemory = $Config.ContainerApps.Memory
$ContainerAppsReplicaTimeout = $Config.ContainerApps.ReplicaTimeout
$ContainerAppsReplicaRetryLimit = $Config.ContainerApps.ReplicaRetryLimit
$ContainerAppsParallelism = $Config.ContainerApps.Parallelism
$ContainerAppsReplicaCompletionCount = $Config.ContainerApps.ReplicaCompletionCount

$SqlServerName = $Config.Sql.ServerName
$SqlServerResourceGroupName = $Config.Sql.ResourceGroupName
$SqlDatabases = $Config.Sql.Databases

$StorageAccounts = $Config.StorageAccounts

# =========================
# STAGE DEFINITIONS
# =========================
$Script:StageOrder = @(
    "SetSubscription",
    "ValidateInputs",
    "EnsurePrimaryResourceGroup",
    "EnsureExtensions",
    "EnsureProviders",
    "EnsureContainerRegistry",
    "BuildAndPushImage",
    "EnsureContainerAppsEnvironment",
    "EnsureContainerAppsJob",
    "EnsureManagedIdentity",
    "EnsureBlobRoleAssignments",
    "EnsureAcrPullRoleAssignment",
    "EnsureRegistryConfiguration"
)

# =========================
# HELPER FUNCTIONS
# =========================

function Invoke-AzureCli {
    param(
        [switch]$StreamOutput,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $previousNativeErrorPreference = $null

    if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
        $previousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
        $global:PSNativeCommandUseErrorActionPreference = $false
    }

    try {
        $ErrorActionPreference = "Continue"

        if ($StreamOutput) {
            & $AzureCliPath @Arguments 2>&1 | ForEach-Object {
                Write-Host $_
            }

            $exitCode = $LASTEXITCODE

            return [pscustomobject]@{
                ExitCode = $exitCode
                Output   = @()
                Command  = "az $($Arguments -join ' ')"
            }
        }

        $output = & $AzureCliPath @Arguments 2>&1
        $exitCode = $LASTEXITCODE

        return [pscustomobject]@{
            ExitCode = $exitCode
            Output   = $output
            Command  = "az $($Arguments -join ' ')"
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference

        if ($null -ne $previousNativeErrorPreference) {
            $global:PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
        }
    }
}

function Show-StepHeader {
    param(
        [string]$Title
    )

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor DarkGray
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor DarkGray
}

function Show-CommandResult {
    param(
        [Parameter(Mandatory)]
        $Result
    )

    Write-Host ""
    Write-Host "Command:" -ForegroundColor Yellow
    Write-Host $Result.Command -ForegroundColor Gray

    Write-Host ""
    if ($Result.ExitCode -eq 0) {
        Write-Host "Result: SUCCESS" -ForegroundColor Green
    }
    else {
        Write-Host "Result: FAILURE" -ForegroundColor Red
    }

    $outputText = if ($null -eq $Result.Output) {
        ""
    }
    else {
        ($Result.Output | Out-String).Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($outputText)) {
        Write-Host ""
        Write-Host "Output:" -ForegroundColor Yellow
        Write-Host $outputText
    }
}

function Pause-ForInspection {
    if ($NonInteractive) {
        return
    }

    while ($true) {
        Write-Host ""
        $choice = Read-Host "Press C to continue or X to cancel"

        switch ($choice.Trim().ToUpperInvariant()) {
            "C" { return }
            "X" { throw "Script cancelled by user." }
            default { Write-Host "Invalid choice. Enter C or X." -ForegroundColor Yellow }
        }
    }
}

function Run-Step {
    param(
        [string]$Title,
        [scriptblock]$Action,
        [switch]$PauseAfter
    )

    Show-StepHeader -Title $Title

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $result = & $Action
    $stopwatch.Stop()

    Show-CommandResult -Result $result

    Write-Host ""
    Write-Host ("Elapsed time: {0:mm\:ss}" -f $stopwatch.Elapsed) -ForegroundColor Cyan

    if ($result.ExitCode -ne 0) {
        throw "Step failed: $Title"
    }

    if ($PauseAfter) {
        Pause-ForInspection
    }

    return $result
}

function Run-StreamingStep {
    param(
        [string]$Title,
        [string]$StartMessage,
        [string]$SuccessMessage,
        [string]$FailureMessage,
        [scriptblock]$Action,
        [switch]$PauseAfter
    )

    Show-StepHeader -Title $Title

    Write-Host $StartMessage -ForegroundColor Yellow
    Write-Host ""

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $result = & $Action
    $stopwatch.Stop()

    Write-Host ""
    if ($result.ExitCode -eq 0) {
        Write-Host $SuccessMessage -ForegroundColor Green
    }
    else {
        Write-Host $FailureMessage -ForegroundColor Red
    }

    Show-CommandResult -Result $result

    Write-Host ""
    Write-Host ("Elapsed time: {0:mm\:ss}" -f $stopwatch.Elapsed) -ForegroundColor Cyan

    if ($result.ExitCode -ne 0) {
        throw "Step failed: $Title"
    }

    if ($PauseAfter) {
        Pause-ForInspection
    }

    return $result
}

function Get-ExistingResourceValue {
    param(
        [string[]]$Arguments
    )

    $result = Invoke-AzureCli @Arguments

    if ($result.ExitCode -ne 0) {
        return $null
    }

    $text = ($result.Output | Out-String).Trim()

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text
}

function Test-StageNameIsValid {
    param(
        [string]$StageName,
        [string]$ParameterName
    )

    if ([string]::IsNullOrWhiteSpace($StageName)) {
        return
    }

    if ($Script:StageOrder -notcontains $StageName) {
        throw "Invalid value for ${ParameterName}: '$StageName'. Valid values: $($Script:StageOrder -join ', ')"
    }
}

function Get-StageIndex {
    param(
        [string]$StageName
    )

    return [Array]::IndexOf($Script:StageOrder, $StageName)
}

function Should-RunStage {
    param(
        [string]$StageName
    )

    $currentIndex = Get-StageIndex -StageName $StageName
    $startIndex = Get-StageIndex -StageName $StartAt
    $stopIndex = if ([string]::IsNullOrWhiteSpace($StopAfter)) {
        $Script:StageOrder.Count - 1
    }
    else {
        Get-StageIndex -StageName $StopAfter
    }

    if ($currentIndex -lt 0) {
        throw "Unknown stage '$StageName'."
    }

    return ($currentIndex -ge $startIndex -and $currentIndex -le $stopIndex)
}

function Ensure-ResourceProviderRegistered {
    param(
        [string]$Namespace
    )

    Show-StepHeader -Title "Ensuring resource provider '$Namespace' is registered"

    $showResult = Invoke-AzureCli provider show `
        --namespace $Namespace `
        --query registrationState `
        --output tsv

    Show-CommandResult -Result $showResult

    if ($showResult.ExitCode -ne 0) {
        throw "Failed to retrieve registration state for provider '$Namespace'."
    }

    $registrationState = ($showResult.Output | Out-String).Trim()

    if ($registrationState -eq "Registered") {
        Write-Host "Resource provider '$Namespace' is already registered." -ForegroundColor Green
        Pause-ForInspection
        return
    }

    $registerResult = Invoke-AzureCli provider register `
        --namespace $Namespace

    Show-CommandResult -Result $registerResult

    if ($registerResult.ExitCode -ne 0) {
        throw "Failed to register resource provider '$Namespace'."
    }

    Write-Host "Waiting for provider '$Namespace' registration to complete..." -ForegroundColor Yellow

    do {
        Start-Sleep -Seconds 5

        $pollResult = Invoke-AzureCli provider show `
            --namespace $Namespace `
            --query registrationState `
            --output tsv

        if ($pollResult.ExitCode -ne 0) {
            Show-CommandResult -Result $pollResult
            throw "Failed while polling registration state for provider '$Namespace'."
        }

        $registrationState = ($pollResult.Output | Out-String).Trim()
        Write-Host "Current registration state for '$Namespace': $registrationState"
    }
    while ($registrationState -ne "Registered")

    Write-Host "Resource provider '$Namespace' is now registered." -ForegroundColor Green
    Pause-ForInspection
}

function Ensure-ContainerAppsExtension {
    Show-StepHeader -Title "Checking Azure Container Apps extension"

    $listResult = Invoke-AzureCli extension list `
        --query "[?name=='containerapp'].name" `
        --output tsv

    Show-CommandResult -Result $listResult

    if ($listResult.ExitCode -ne 0) {
        throw "Failed to query Azure CLI extensions."
    }

    $installedExtensionName = ($listResult.Output | Out-String).Trim()

    if ($installedExtensionName -eq "containerapp") {
        Write-Host "Azure Container Apps extension is already installed." -ForegroundColor Green
        Pause-ForInspection
        return
    }

    $installResult = Run-Step -Title "Installing Azure Container Apps extension" -PauseAfter {
        Invoke-AzureCli extension add --name containerapp
    }

    return $installResult
}

function Ensure-RoleAssignment {
    param(
        [string]$PrincipalObjectId,
        [string]$RoleName,
        [string]$Scope,
        [string]$Description
    )

    Show-StepHeader -Title $Description

    $existing = Invoke-AzureCli role assignment list `
        --assignee-object-id $PrincipalObjectId `
        --role $RoleName `
        --scope $Scope `
        --query "[].id" `
        --output tsv

    if ($existing.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace(($existing.Output | Out-String).Trim())) {
        Write-Host "Role assignment already exists. Skipping." -ForegroundColor Green
        Show-CommandResult -Result $existing
        Pause-ForInspection
        return
    }

    $createResult = Invoke-AzureCli role assignment create `
        --assignee-object-id $PrincipalObjectId `
        --assignee-principal-type ServicePrincipal `
        --role $RoleName `
        --scope $Scope

    Show-CommandResult -Result $createResult

    if ($createResult.ExitCode -ne 0) {
        throw "Failed to create role assignment for role '$RoleName' on scope '$Scope'."
    }

    Pause-ForInspection
}

function Ensure-DockerfileExists {
    param(
        [string]$Path
    )

    Show-StepHeader -Title "Validating Dockerfile path"

    if (-not (Test-Path $Path)) {
        Write-Host "Dockerfile not found at path: $Path" -ForegroundColor Red
        throw "Dockerfile validation failed."
    }

    Write-Host "Dockerfile found at: $Path" -ForegroundColor Green
    Pause-ForInspection
}

function Ensure-StorageAccountExists {
    param(
        [string]$StorageAccountName,
        [string]$StorageAccountResourceGroupName
    )

    Show-StepHeader -Title "Validating storage account '$StorageAccountName'"

    $result = Invoke-AzureCli storage account show `
        --name $StorageAccountName `
        --resource-group $StorageAccountResourceGroupName `
        --query id `
        --output tsv

    Show-CommandResult -Result $result

    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace(($result.Output | Out-String).Trim())) {
        throw "Storage account '$StorageAccountName' not found in resource group '$StorageAccountResourceGroupName'."
    }

    Pause-ForInspection

    return ($result.Output | Out-String).Trim()
}

function Ensure-SqlServerExists {
    param(
        [string]$SqlServerFullyQualifiedName,
        [string]$SqlServerResourceGroupName
    )

    Show-StepHeader -Title "Validating Structured Query Language server '$SqlServerFullyQualifiedName'"

    $sqlServerShortName = $SqlServerFullyQualifiedName.Split('.')[0]

    $result = Invoke-AzureCli sql server show `
        --name $sqlServerShortName `
        --resource-group $SqlServerResourceGroupName `
        --query id `
        --output tsv

    Show-CommandResult -Result $result

    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace(($result.Output | Out-String).Trim())) {
        throw "Structured Query Language server '$SqlServerFullyQualifiedName' not found in resource group '$SqlServerResourceGroupName'."
    }

    Pause-ForInspection

    return ($result.Output | Out-String).Trim()
}

function Ensure-SqlDatabaseExists {
    param(
        [string]$SqlServerFullyQualifiedName,
        [string]$SqlServerResourceGroupName,
        [string]$SqlDatabaseName
    )

    Show-StepHeader -Title "Validating Structured Query Language database '$SqlDatabaseName'"

    $sqlServerShortName = $SqlServerFullyQualifiedName.Split('.')[0]

    $result = Invoke-AzureCli sql db show `
        --server $sqlServerShortName `
        --resource-group $SqlServerResourceGroupName `
        --name $SqlDatabaseName `
        --query id `
        --output tsv

    Show-CommandResult -Result $result

    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace(($result.Output | Out-String).Trim())) {
        throw "Structured Query Language database '$SqlDatabaseName' not found on server '$SqlServerFullyQualifiedName'."
    }

    Pause-ForInspection

    return ($result.Output | Out-String).Trim()
}

function Get-ContainerAppsJobPrincipalId {
    $result = Invoke-AzureCli containerapp job identity show `
        --name $ContainerAppsJobName `
        --resource-group $PrimaryResourceGroupName `
        --query principalId `
        --output tsv

    if ($result.ExitCode -ne 0) {
        Show-CommandResult -Result $result
        throw "Could not retrieve the managed identity principal ID for job '$ContainerAppsJobName'."
    }

    $principalId = ($result.Output | Out-String).Trim()

    if ([string]::IsNullOrWhiteSpace($principalId)) {
        throw "Managed identity principal ID is empty for job '$ContainerAppsJobName'."
    }

    return $principalId
}

# =========================
# VALIDATE STAGE PARAMETERS
# =========================
Test-StageNameIsValid -StageName $StartAt -ParameterName "StartAt"
Test-StageNameIsValid -StageName $StopAfter -ParameterName "StopAfter"

if (-not [string]::IsNullOrWhiteSpace($StopAfter)) {
    $startIndex = Get-StageIndex -StageName $StartAt
    $stopIndex = Get-StageIndex -StageName $StopAfter

    if ($stopIndex -lt $startIndex) {
        throw "StopAfter '$StopAfter' cannot come before StartAt '$StartAt'."
    }
}

# =========================
# SCRIPT START
# =========================

if (Should-RunStage -StageName "SetSubscription") {
    Run-Step -Title "Setting Azure subscription" -PauseAfter {
        Invoke-AzureCli account set --subscription $SubscriptionId
    }
}

if (Should-RunStage -StageName "ValidateInputs") {
    # -------------------------
    # Validation section
    # -------------------------
    Ensure-DockerfileExists -Path $DockerfilePath
    Ensure-SqlServerExists -SqlServerFullyQualifiedName $SqlServerName -SqlServerResourceGroupName $SqlServerResourceGroupName

    foreach ($databaseProperty in $SqlDatabases.PSObject.Properties) {
        Ensure-SqlDatabaseExists `
            -SqlServerFullyQualifiedName $SqlServerName `
            -SqlServerResourceGroupName $SqlServerResourceGroupName `
            -SqlDatabaseName $databaseProperty.Value
    }

    foreach ($storageAccount in $StorageAccounts) {
        Ensure-StorageAccountExists `
            -StorageAccountName $storageAccount.Name `
            -StorageAccountResourceGroupName $storageAccount.ResourceGroupName
    }
}

if (Should-RunStage -StageName "EnsurePrimaryResourceGroup") {
    # -------------------------
    # Primary resource group
    # -------------------------
    $resourceGroupExists = Get-ExistingResourceValue -Arguments @(
        "group", "exists",
        "--name", $PrimaryResourceGroupName
    )

    if ($resourceGroupExists -eq "true") {
        Show-StepHeader -Title "Azure resource group already exists"
        Write-Host "Resource group '$PrimaryResourceGroupName' already exists." -ForegroundColor Green
        Pause-ForInspection
    }
    else {
        Run-Step -Title "Creating Azure resource group" -PauseAfter {
            Invoke-AzureCli group create `
                --name $PrimaryResourceGroupName `
                --location $PrimaryResourceGroupLocation
        }
    }
}

if (Should-RunStage -StageName "EnsureExtensions") {
    Ensure-ContainerAppsExtension
}

if (Should-RunStage -StageName "EnsureProviders") {
    Ensure-ResourceProviderRegistered -Namespace "Microsoft.ContainerRegistry"
    Ensure-ResourceProviderRegistered -Namespace "Microsoft.App"
    Ensure-ResourceProviderRegistered -Namespace "Microsoft.OperationalInsights"
}

if (Should-RunStage -StageName "EnsureContainerRegistry") {
    # -------------------------
    # Azure Container Registry
    # -------------------------
    $existingContainerRegistryId = Get-ExistingResourceValue -Arguments @(
        "acr", "show",
        "--name", $ContainerRegistryName,
        "--resource-group", $PrimaryResourceGroupName,
        "--query", "id",
        "--output", "tsv"
    )

    if ($existingContainerRegistryId) {
        Show-StepHeader -Title "Azure Container Registry already exists"
        Write-Host "Registry '$ContainerRegistryName' already exists." -ForegroundColor Green
        Write-Host "Resource ID: $existingContainerRegistryId"
        Pause-ForInspection
    }
    else {
        Run-Step -Title "Creating Azure Container Registry" -PauseAfter {
            Invoke-AzureCli acr create `
                --resource-group $PrimaryResourceGroupName `
                --name $ContainerRegistryName `
                --sku $ContainerRegistrySku `
                --location $PrimaryResourceGroupLocation `
                --admin-enabled false
        }
    }
}

if (Should-RunStage -StageName "BuildAndPushImage") {
    # -------------------------
    # Build and push image
    # -------------------------
    Run-StreamingStep `
        -Title "Building and pushing Backfiller container image to Azure Container Registry" `
        -StartMessage "Starting remote build and image push. This may take several minutes..." `
        -SuccessMessage "Remote build finished successfully." `
        -FailureMessage "Remote build failed." `
        -PauseAfter {
            Invoke-AzureCli -StreamOutput acr build `
                --registry $ContainerRegistryName `
                --image $VersionedContainerImageName `
                --image $LatestContainerImageName `
                --file $DockerfilePath `
                .
        }
}

if (Should-RunStage -StageName "EnsureContainerAppsEnvironment") {
    # -------------------------
    # Container Apps environment
    # -------------------------
    $existingContainerAppsEnvironmentId = Get-ExistingResourceValue -Arguments @(
        "containerapp", "env", "show",
        "--name", $ContainerAppsEnvironmentName,
        "--resource-group", $PrimaryResourceGroupName,
        "--query", "id",
        "--output", "tsv"
    )

    if ($existingContainerAppsEnvironmentId) {
        Show-StepHeader -Title "Azure Container Apps environment already exists"
        Write-Host "Environment '$ContainerAppsEnvironmentName' already exists." -ForegroundColor Green
        Write-Host "Resource ID: $existingContainerAppsEnvironmentId"
        Pause-ForInspection
    }
    else {
        Run-StreamingStep `
            -Title "Creating Azure Container Apps environment" `
            -StartMessage "Starting Azure Container Apps environment creation. This may take several minutes..." `
            -SuccessMessage "Azure Container Apps environment created successfully." `
            -FailureMessage "Azure Container Apps environment creation failed." `
            -PauseAfter {
                Invoke-AzureCli -StreamOutput containerapp env create `
                    --name $ContainerAppsEnvironmentName `
                    --resource-group $PrimaryResourceGroupName `
                    --location $PrimaryResourceGroupLocation
            }
    }
}

if (Should-RunStage -StageName "EnsureContainerAppsJob") {
    # -------------------------
    # Container Apps Job
    # -------------------------
    $existingJobId = Get-ExistingResourceValue -Arguments @(
        "containerapp", "job", "show",
        "--name", $ContainerAppsJobName,
        "--resource-group", $PrimaryResourceGroupName,
        "--query", "id",
        "--output", "tsv"
    )

    if ($existingJobId) {
        Show-StepHeader -Title "Azure Container Apps Job already exists"
        Write-Host "Job '$ContainerAppsJobName' already exists." -ForegroundColor Green
        Write-Host "Resource ID: $existingJobId"
        Pause-ForInspection
    }
    else {
        Run-StreamingStep `
            -Title "Creating manual Azure Container Apps Job" `
            -StartMessage "Starting Azure Container Apps Job creation. This may take several minutes..." `
            -SuccessMessage "Azure Container Apps Job created successfully." `
            -FailureMessage "Azure Container Apps Job creation failed." `
            -PauseAfter {
                Invoke-AzureCli -StreamOutput containerapp job create `
                    --name $ContainerAppsJobName `
                    --resource-group $PrimaryResourceGroupName `
                    --environment $ContainerAppsEnvironmentName `
                    --trigger-type Manual `
                    --replica-timeout $ContainerAppsReplicaTimeout `
                    --replica-retry-limit $ContainerAppsReplicaRetryLimit `
                    --replica-completion-count $ContainerAppsReplicaCompletionCount `
                    --parallelism $ContainerAppsParallelism `
                    --image $FullyQualifiedContainerImageName `
                    --cpu $ContainerAppsJobCpu `
                    --memory $ContainerAppsJobMemory `
                    --env-vars `
                        SQL_SERVER=$SqlServerName `
                        CII_SQL_DATABASE=$SqlDatabases.CII `
                        CSI_SQL_DATABASE=$SqlDatabases.CSI `
                        DSI_SQL_DATABASE=$SqlDatabases.DSI `
                        DSN_SQL_DATABASE=$SqlDatabases.DSN `
                        CII_BLOB_ACCOUNT_URL=$($StorageAccounts | Where-Object { $_.Code -eq "CII" } | Select-Object -ExpandProperty BlobAccountUrl) `
                        CSI_BLOB_ACCOUNT_URL=$($StorageAccounts | Where-Object { $_.Code -eq "CSI" } | Select-Object -ExpandProperty BlobAccountUrl) `
                        DSI_BLOB_ACCOUNT_URL=$($StorageAccounts | Where-Object { $_.Code -eq "DSI" } | Select-Object -ExpandProperty BlobAccountUrl) `
                        DSN_BLOB_ACCOUNT_URL=$($StorageAccounts | Where-Object { $_.Code -eq "DSN" } | Select-Object -ExpandProperty BlobAccountUrl)
            }
    }
}

if (Should-RunStage -StageName "EnsureManagedIdentity") {
    # -------------------------
    # Managed identity
    # -------------------------
    Run-Step -Title "Assigning system-managed identity to Azure Container Apps Job" -PauseAfter {
        Invoke-AzureCli containerapp job identity assign `
            --name $ContainerAppsJobName `
            --resource-group $PrimaryResourceGroupName `
            --system-assigned
    }

    $jobIdentityResult = Run-Step -Title "Retrieving Azure Container Apps Job principal ID" -PauseAfter {
        Invoke-AzureCli containerapp job identity show `
            --name $ContainerAppsJobName `
            --resource-group $PrimaryResourceGroupName `
            --query principalId `
            --output tsv
    }

    $ContainerAppsJobPrincipalId = ($jobIdentityResult.Output | Out-String).Trim()

    if ([string]::IsNullOrWhiteSpace($ContainerAppsJobPrincipalId)) {
        throw "Could not retrieve the managed identity principal ID for job '$ContainerAppsJobName'."
    }
}

if (Should-RunStage -StageName "EnsureBlobRoleAssignments") {
    # -------------------------
    # Blob role assignments
    # -------------------------
    $ContainerAppsJobPrincipalId = Get-ContainerAppsJobPrincipalId

    foreach ($storageAccount in $StorageAccounts) {
        $storageAccountShowResult = Run-Step -Title "Retrieving resource ID for storage account '$($storageAccount.Name)'" -PauseAfter {
            Invoke-AzureCli storage account show `
                --name $storageAccount.Name `
                --resource-group $storageAccount.ResourceGroupName `
                --query id `
                --output tsv
        }

        $StorageAccountResourceId = ($storageAccountShowResult.Output | Out-String).Trim()

        if ([string]::IsNullOrWhiteSpace($StorageAccountResourceId)) {
            throw "Could not retrieve the resource ID for storage account '$($storageAccount.Name)'."
        }

        Ensure-RoleAssignment `
            -PrincipalObjectId $ContainerAppsJobPrincipalId `
            -RoleName "Storage Blob Data Reader" `
            -Scope $StorageAccountResourceId `
            -Description "Ensuring Blob Storage role assignment for storage account '$($storageAccount.Name)'"
    }
}

if (Should-RunStage -StageName "EnsureAcrPullRoleAssignment") {
    # -------------------------
    # Azure Container Registry role assignment
    # -------------------------
    $ContainerAppsJobPrincipalId = Get-ContainerAppsJobPrincipalId

    $containerRegistryShowResult = Run-Step -Title "Retrieving Azure Container Registry resource ID" -PauseAfter {
        Invoke-AzureCli acr show `
            --name $ContainerRegistryName `
            --resource-group $PrimaryResourceGroupName `
            --query id `
            --output tsv
    }

    $ContainerRegistryResourceId = ($containerRegistryShowResult.Output | Out-String).Trim()

    if ([string]::IsNullOrWhiteSpace($ContainerRegistryResourceId)) {
        throw "Could not retrieve the resource ID for registry '$ContainerRegistryName'."
    }

    Ensure-RoleAssignment `
        -PrincipalObjectId $ContainerAppsJobPrincipalId `
        -RoleName "AcrPull" `
        -Scope $ContainerRegistryResourceId `
        -Description "Ensuring AcrPull role assignment for Azure Container Registry"
}

if (Should-RunStage -StageName "EnsureRegistryConfiguration") {
    # -------------------------
    # Registry config on job
    # -------------------------
    Run-Step -Title "Configuring Azure Container Apps Job to pull image from Azure Container Registry using system-managed identity" -PauseAfter {
        Invoke-AzureCli containerapp job registry set `
            --name $ContainerAppsJobName `
            --resource-group $PrimaryResourceGroupName `
            --server "$ContainerRegistryName.azurecr.io" `
            --identity system
    }
}

Write-Host ""
Write-Host "Requested stages completed." -ForegroundColor Green
Write-Host ""
Write-Host "Available stage names:" -ForegroundColor Cyan
Write-Host ($Script:StageOrder -join ", ")
Write-Host ""
Write-Host "Examples:" -ForegroundColor Cyan
Write-Host "  .\provision-documentcatalog-backfiller-azure.ps1 -StartAt BuildAndPushImage -StopAfter BuildAndPushImage"
Write-Host "  .\provision-documentcatalog-backfiller-azure.ps1 -StartAt EnsureContainerAppsEnvironment"
Write-Host ""
Write-Host "Next manual test command:" -ForegroundColor Cyan
Write-Host ""
Write-Host "az containerapp job start --name $ContainerAppsJobName --resource-group $PrimaryResourceGroupName --args --company CII --dry-run"