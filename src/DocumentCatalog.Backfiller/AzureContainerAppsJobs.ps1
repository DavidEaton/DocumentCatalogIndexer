$SubscriptionId = "52a72d69-08ab-45ea-8f23-da9245367cf6"
$ResourceGroupName = "DocumentCatalogIndexer" # documentcatalog-backfiller Only runs manually, infrequently and to initialize and index the document catalog functionality, so we can use the same resource group for both the function app and the container apps job.
$AzureRegion = "eastus"   # example: eastus

# Azure Container Registry (ACR)
$ContainerRegistryName = "eedocsacr"

# Container image and respository - create our own respository of container images within the ACR
$ContainerImageRepositoryName = "DocumentCatalog" # 
$VersionedContainerImageName = "$ContainerImageRepositoryName:2026.04.04.1"
$LatestContainerImageName = "$ContainerImageRepositoryName:latest"
$FullyQualifiedContainerImageName = "$ContainerRegistryName.azurecr.io/$ContainerImageRepositoryName:2026.04.04.1"
Write-Host ""
Write-Host "ContainerImageRepositoryName: $ContainerImageRepositoryName"

# Azure Container Apps Environment/Jobs
$ContainerAppsEnvironmentName = "container-apps-env-ee-docs"
$ContainerAppsJobName = "documentcatalog-backfiller" # ...as in, the job of this container app is to back-fill the document catalog.

# SQL configuration (non-secret)
$SqlDatabaseServer = "e04vmu8qq9.database.windows.net"
$CiiSqlDatabase = "CiiSql"
$CsiSqlDatabase = "CsiSql"
$DsiSqlDatabase = "DsiSql"
$DsnSqlDatabase = "DsnSql"
Write-Host ""
Write-Host "SQL Database server: $SqlDatabaseServer"

# Four Companies, four storage account URLs (non-secret)
$CiiBlobAccountUrl = "https://cii.blob.core.windows.net/"
$CsiBlobAccountUrl = "https://csii.blob.core.windows.net/"
$DsiBlobAccountUrl = "https://dsii.blob.core.windows.net/"
$DsnBlobAccountUrl = "https://dsni.blob.core.windows.net/"

$AzureCliPath = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"

# Helper for calling Azure CLI
function Invoke-AzureCli {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $AzureCliPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }
}

Write-Host ""
Write-Host "Setting Azure subscription..."
Invoke-AzureCli account set --subscription $SubscriptionId

Write-Host ""
Write-Host "Creating Azure Container Registry..."
Invoke-AzureCli acr create `
    --resource-group $ResourceGroupName `
    --name $ContainerRegistryName `
    --sku Basic `
    --location $AzureRegion `
    --admin-enabled false

Write-Host ""
Write-Host "Building and pushing Backfiller container image to Azure Container Registry..."
Invoke-AzureCli acr build `
    --registry $ContainerRegistryName `
    --image $VersionedContainerImageName `
    --image $LatestContainerImageName `
    --file src/DocumentCatalog.Backfiller/Dockerfile `

Write-Host ""
Write-Host "Creating Azure Container Apps environment..."
Invoke-AzureCli containerapp env create `
    --name $ContainerAppsEnvironmentName `
    --resource-group $ResourceGroupName `
    --location $AzureRegion

Write-Host ""
Write-Host "Creating manual Azure Container Apps job..."
Invoke-AzureCli containerapp job create `
    --name $ContainerAppsJobName `
    --resource-group $ResourceGroupName `
    --environment $ContainerAppsEnvironmentName `
    --trigger-type Manual `
    --replica-timeout 1800 `
    --replica-retry-limit 1 `
    --replica-completion-count 1 `
    --parallelism 1 `
    --image $FullyQualifiedContainerImageName `
    --cpu 0.5 `
    --memory 1.0Gi `
    --env-vars `
        SQL_SERVER=$SqlDatabaseServer `
        CII_SQL_DATABASE=$CiiSqlDatabase `
        CSI_SQL_DATABASE=$CsiSqlDatabase `
        DSI_SQL_DATABASE=$DsiSqlDatabase `
        DSN_SQL_DATABASE=$DsnSqlDatabase `
        CII_BLOB_ACCOUNT_URL=$CiiBlobAccountUrl `
        CSI_BLOB_ACCOUNT_URL=$CsiBlobAccountUrl `
        DSI_BLOB_ACCOUNT_URL=$DsiBlobAccountUrl `
        DSN_BLOB_ACCOUNT_URL=$DsnBlobAccountUrl

Write-Host ""
Write-Host "Assigning system-managed identity to Azure Container Apps job..."
Invoke-AzureCli containerapp job identity assign `
    --name $ContainerAppsJobName `
    --resource-group $ResourceGroupName `
    --system-assigned

Write-Host ""
Write-Host "Retrieving Azure Container Apps job principal ID..."
$ContainerAppsJobPrincipalId = Invoke-AzureCli containerapp job identity show `
    --name $ContainerAppsJobName `
    --resource-group $ResourceGroupName `
    --query principalId `
    --output tsv

Write-Host ""
Write-Host "Retrieving Azure Container Registry resource ID..."
$ContainerRegistryResourceId = Invoke-AzureCli acr show `
    --name $ContainerRegistryName `
    --resource-group $ResourceGroupName `
    --query id `
    --output tsv

Write-Host ""
Write-Host "Granting AcrPull to Azure Container Apps job identity..."
Invoke-AzureCli role assignment create `
    --assignee-object-id $ContainerAppsJobPrincipalId `
    --assignee-principal-type ServicePrincipal `
    --role AcrPull `
    --scope $ContainerRegistryResourceId

Write-Host ""
Write-Host "Configuring Azure Container Apps job to pull image from Azure Container Registry using system-managed identity..."
Invoke-AzureCli containerapp job registry set `
    --name $ContainerAppsJobName `
    --resource-group $ResourceGroupName `
    --server "$ContainerRegistryName.azurecr.io" `
    --identity system

Write-Host ""
Write-Host "Done."
Write-Host ""
Write-Host "Next manual test command:"
Write-Host ""
Write-Host "az containerapp job start --name $ContainerAppsJobName --resource-group $ResourceGroupName --args --company CII --dry-run"