using System.Data;
using Azure;
using Azure.Storage.Blobs.Models;
using DocumentCatalog.IndexerFunctions.Models;
using DocumentCatalog.Shared;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace DocumentCatalog.Backfiller;

public sealed class CatalogBackfillService(
    IBlobClientFactory blobClientFactory,
    ISqlConnectionStringFactory sqlConnectionStringFactory,
    ILogger<CatalogBackfillService> logger) : ICatalogBackfillService
{
    private readonly IBlobClientFactory _blobClientFactory = blobClientFactory;
    private readonly ISqlConnectionStringFactory _sqlConnectionStringFactory = sqlConnectionStringFactory;
    private readonly ILogger<CatalogBackfillService> _logger = logger;

    private const string ContainerName = "hrdocs";
    private const int ProgressInterval = 250;
    private const string CommandText = "HR.EmployeeDocumentCatalogUpsertFromBlobEvent";

    public async Task<BackfillResult> BackfillCompanyAsync(
        string company,
        bool dryRun,
        CancellationToken cancellationToken)
    {
        var accountUrl = _blobClientFactory.GetAccountUrl(company);
        var credentialMode = _blobClientFactory.GetCredentialMode();

        _logger.LogInformation(
            "Resolved configuration for company {Company}. BlobAccountUrl={BlobAccountUrl} Container={ContainerName} DryRun={DryRun} CredentialMode={CredentialMode}",
            company,
            accountUrl,
            ContainerName,
            dryRun,
            credentialMode);

        var container = _blobClientFactory.CreateContainerClient(company, ContainerName);

        Response<bool> existsResponse;
        try
        {
            existsResponse = await container.ExistsAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                $"Unable to verify existence of container '{ContainerName}' for company '{company}'.",
                ex);
        }

        _logger.LogInformation(
            "Container '{ContainerName}' exists for company {Company}: {Exists}",
            ContainerName,
            company,
            existsResponse.Value);

        if (!existsResponse.Value)
        {
            throw new InvalidOperationException(
                $"Container '{ContainerName}' does not exist for company '{company}' at '{accountUrl}'.");
        }

        var examined = 0;
        var candidates = 0;
        var upserted = 0;
        var skippedInvalidName = 0;
        var sqlFailures = 0;

        await foreach (var blobItem in container.GetBlobsAsync(
            traits: BlobTraits.None,
            states: BlobStates.None,
            prefix: null,
            cancellationToken: cancellationToken))
        {
            examined++;

            if (!DocumentBlobParser.TryParseEmployeeDocumentBlobName(
                    blobItem.Name,
                    out var employeeId,
                    out var documentTypeToken))
            {
                skippedInvalidName++;

                _logger.LogDebug(
                    "Skipping blob {BlobName} for company {Company}; name does not match expected convention.",
                    blobItem.Name,
                    company);

                continue;
            }

            candidates++;

            var documentTypeDisplay = DocumentBlobParser.HumanizeDocumentType(documentTypeToken);
            var blobNameHash = DocumentBlobParser.ComputeBlobNameHash(blobItem.Name);

            var item = new BlobCatalogItem(
                Company: company,
                BlobName: blobItem.Name,
                BlobNameHash: blobNameHash,
                EmployeeId: employeeId,
                DocumentTypeToken: documentTypeToken,
                DocumentTypeDisplay: documentTypeDisplay,
                UpdatedUtc: blobItem.Properties.LastModified,
                ContentType: blobItem.Properties.ContentType,
                BlobETag: blobItem.Properties.ETag?.ToString());

            if (dryRun)
            {
                _logger.LogDebug(
                    "[DryRun] Would upsert blob {BlobName} for company {Company}. EmployeeId={EmployeeId} DocumentType={DocumentType}",
                    item.BlobName,
                    company,
                    item.EmployeeId,
                    item.DocumentTypeToken);

                upserted++;
            }
            else
            {
                try
                {
                    await UpsertAsync(item, cancellationToken);
                    upserted++;
                }
                catch (Exception ex)
                {
                    sqlFailures++;

                    _logger.LogError(
                        ex,
                        "SQL upsert failed for company {Company}, blob {BlobName}, employee {EmployeeId}, document type {DocumentType}.",
                        company,
                        item.BlobName,
                        item.EmployeeId,
                        item.DocumentTypeToken);
                }
            }

            if (examined % ProgressInterval == 0)
            {
                _logger.LogInformation(
                    "Progress for company {Company}: Examined={Examined} Candidates={Candidates} Upserted={Upserted} SkippedInvalidName={SkippedInvalidName} SqlFailures={SqlFailures}",
                    company,
                    examined,
                    candidates,
                    upserted,
                    skippedInvalidName,
                    sqlFailures);
            }
        }

        if (examined == 0)
        {
            throw new InvalidOperationException(
                $"Container '{ContainerName}' for company '{company}' is reachable but enumeration returned zero blobs. Verify the deployed image, credential selection, storage networking rules, and the target account URL.");
        }

        if (candidates == 0 && examined > 0)
        {
            _logger.LogWarning(
                "Enumerated blobs for company {Company}, but none matched the expected naming convention.",
                company);
        }

        if (!dryRun && sqlFailures > 0)
        {
            _logger.LogWarning(
                "Backfill completed for company {Company} with SQL failures. SqlFailures={SqlFailures}",
                company,
                sqlFailures);
        }

        return new BackfillResult(
            Examined: examined,
            Candidates: candidates,
            Upserted: upserted,
            SkippedInvalidName: skippedInvalidName,
            SqlFailures: sqlFailures);
    }

    private async Task UpsertAsync(
        BlobCatalogItem item,
        CancellationToken cancellationToken)
    {
        var connectionString = _sqlConnectionStringFactory.Create(item.Company);

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var command = new SqlCommand(
            CommandText,
            connection)
        {
            CommandType = CommandType.StoredProcedure,
            CommandTimeout = 60
        };

        command.Parameters.AddWithValue("@BlobName", item.BlobName);
        command.Parameters.AddWithValue("@BlobNameHash", item.BlobNameHash);
        command.Parameters.AddWithValue("@EmployeeId", item.EmployeeId);
        command.Parameters.AddWithValue("@DocumentTypeToken", item.DocumentTypeToken);
        command.Parameters.AddWithValue("@DocumentTypeDisplay", item.DocumentTypeDisplay);
        command.Parameters.AddWithValue("@UpdatedUtc", (object?)item.UpdatedUtc ?? DBNull.Value);
        command.Parameters.AddWithValue("@ContentType", (object?)item.ContentType ?? DBNull.Value);
        command.Parameters.AddWithValue("@BlobETag", (object?)item.BlobETag ?? DBNull.Value);

        await command.ExecuteNonQueryAsync(cancellationToken);

        _logger.LogDebug(
            "Upserted blob {BlobName} for company {Company} with {command.CommandTimeout} CommandTimeout.",
            item.BlobName,
            item.Company,
            command.CommandTimeout);
    }
}

public sealed record BackfillResult(
    int Examined,
    int Candidates,
    int Upserted,
    int SkippedInvalidName,
    int SqlFailures);
