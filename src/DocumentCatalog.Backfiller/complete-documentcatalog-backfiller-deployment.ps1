[CmdletBinding()]
param(
    [string]$ConfigPath = ".\provision-documentcatalog-backfiller-azure.config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

$AzureCliPath = $Config.AzureCliPath
$SubscriptionId = $Config.SubscriptionId

$RG = $Config.ResourceGroup.Name
$ACR = $Config.ContainerRegistry.Name

$EnvName = $Config.ContainerApps.EnvironmentName
$JobName = $Config.ContainerApps.JobName

$Image = "$($ACR).azurecr.io/$($Config.ContainerImage.RepositoryName):$($Config.ContainerImage.Tag)"

$SqlServer = $Config.Sql.ServerName
$SqlDatabases = $Config.Sql.Databases
$StorageAccounts = $Config.StorageAccounts

function az {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$args)
    & $AzureCliPath @args
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($args -join ' ')"
    }
}

Write-Host "Using subscription..."
az account set --subscription $SubscriptionId

# -------------------------
# Enable ACR admin (temporary)
# -------------------------
Write-Host "Enabling ACR admin (temporary)..."
az acr update --name $ACR --resource-group $RG --admin-enabled true

$acrUser = az acr credential show --name $ACR --query username --output tsv
$acrPass = az acr credential show --name $ACR --query "passwords[0].value" --output tsv

# -------------------------
# Create job
# -------------------------
Write-Host "Creating Container Apps job..."

az containerapp job create `
  --name $JobName `
  --resource-group $RG `
  --environment $EnvName `
  --trigger-type Manual `
  --image $Image `
  --cpu $Config.ContainerApps.Cpu `
  --memory $Config.ContainerApps.Memory `
  --registry-server "$ACR.azurecr.io" `
  --registry-username $acrUser `
  --registry-password $acrPass `
  --env-vars `
    SQL_SERVER=$SqlServer `
    CII_SQL_DATABASE=$($SqlDatabases.CII) `
    CSI_SQL_DATABASE=$($SqlDatabases.CSI) `
    DSI_SQL_DATABASE=$($SqlDatabases.DSI) `
    DSN_SQL_DATABASE=$($SqlDatabases.DSN)

# -------------------------
# Assign identity
# -------------------------
Write-Host "Assigning managed identity..."

az containerapp job identity assign `
  --name $JobName `
  --resource-group $RG `
  --system-assigned

$principalId = az containerapp job identity show `
  --name $JobName `
  --resource-group $RG `
  --query principalId `
  --output tsv

# -------------------------
# Grant ACR pull
# -------------------------
Write-Host "Granting AcrPull..."

$acrId = az acr show --name $ACR --resource-group $RG --query id --output tsv

az role assignment create `
  --assignee-object-id $principalId `
  --assignee-principal-type ServicePrincipal `
  --role AcrPull `
  --scope $acrId

# -------------------------
# Grant Blob access
# -------------------------
Write-Host "Granting Blob Storage access..."

foreach ($sa in $StorageAccounts) {
    $saId = az storage account show `
        --name $sa.Name `
        --resource-group $sa.ResourceGroupName `
        --query id `
        --output tsv

    az role assignment create `
      --assignee-object-id $principalId `
      --assignee-principal-type ServicePrincipal `
      --role "Storage Blob Data Reader" `
      --scope $saId
}

# -------------------------
# Switch to managed identity
# -------------------------
Write-Host "Switching job to managed identity for ACR..."

az containerapp job registry set `
  --name $JobName `
  --resource-group $RG `
  --server "$ACR.azurecr.io" `
  --identity system

# -------------------------
# Disable ACR admin
# -------------------------
Write-Host "Disabling ACR admin..."

az acr update --name $ACR --resource-group $RG --admin-enabled false

# -------------------------
# Done
# -------------------------
Write-Host ""
Write-Host "SUCCESS: Backfiller job fully provisioned." -ForegroundColor Green
Write-Host ""
Write-Host "Test command:"
Write-Host "az containerapp job start --name $JobName --resource-group $RG --args --company CII --dry-run"