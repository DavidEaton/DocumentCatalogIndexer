using Azure.Storage.Blobs.Models;
using DocumentCatalog.IndexerFunctions.Models;
using DocumentCatalog.Shared;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using System.Data;

namespace DocumentCatalog.Backfiller;

public interface ICatalogBackfillService
{
    Task<BackfillResult> BackfillCompanyAsync(
        Company company,
        bool dryRun,
        int? limit,
        CancellationToken cancellationToken);
}

public sealed class CatalogBackfillService(
    IBlobClientFactory blobClientFactory,
    ISqlConnectionStringFactory sqlConnectionStringFactory,
    ILogger<CatalogBackfillService> logger) : ICatalogBackfillService
{
    private readonly IBlobClientFactory _blobClientFactory = blobClientFactory;
    private readonly ISqlConnectionStringFactory _sqlConnectionStringFactory = sqlConnectionStringFactory;
    private readonly ILogger<CatalogBackfillService> _logger = logger;
    private const string CONTAINERNAME = "hrdocs";

    public async Task<BackfillResult> BackfillCompanyAsync(
        Company company,
        bool dryRun,
        int? limit,
        CancellationToken cancellationToken)
    {
        var container = _blobClientFactory.CreateContainerClient(company, CONTAINERNAME);

        var examined = 0;
        var upserted = 0;
        var skipped = 0;

        await foreach (var blobItem in container.GetBlobsAsync(
            traits: BlobTraits.None,
            states: BlobStates.None,
            prefix: $"{CONTAINERNAME}/",
            cancellationToken: cancellationToken))
        {
            if (limit.HasValue && examined >= limit.Value)
                break;

            examined++;

            if (!DocumentBlobParser.TryParseEmployeeDocumentBlobName(
                    blobItem.Name,
                    out var employeeId,
                    out var documentTypeToken))
            {
                skipped++;
                _logger.LogDebug(
                    "Skipping blob {BlobName} for company {Company}; name does not match expected convention.",
                    blobItem.Name,
                    company);
                continue;
            }

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
                BlobLastModifiedUtc: blobItem.Properties.LastModified,
                ContentType: blobItem.Properties.ContentType,
                BlobETag: blobItem.Properties.ETag?.ToString(),
                IsCatalogCandidate: true);

            if (dryRun)
            {
                _logger.LogInformation(
                    "[DryRun] Would upsert blob {BlobName} for company {Company}.",
                    item.BlobName,
                    company);
                upserted++;
                continue;
            }

            await UpsertAsync(item, cancellationToken);
            upserted++;

            if (upserted % 500 == 0)
            {
                _logger.LogInformation(
                    "Progress for company {Company}: Examined={Examined} Upserted={Upserted} Skipped={Skipped}",
                    company,
                    examined,
                    upserted,
                    skipped);
            }
        }

        return new BackfillResult(examined, upserted, skipped);
    }

    private async Task UpsertAsync(
        BlobCatalogItem item,
        CancellationToken cancellationToken)
    {
        var connectionString = _sqlConnectionStringFactory.Create(item.Company);

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var command = new SqlCommand(
            "Common.usp_EmployeeDocumentCatalog_UpsertFromBlobEvent",
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
        command.Parameters.AddWithValue("@BlobLastModifiedUtc", (object?)item.BlobLastModifiedUtc ?? DBNull.Value);
        command.Parameters.AddWithValue("@ContentType", (object?)item.ContentType ?? DBNull.Value);
        command.Parameters.AddWithValue("@BlobETag", (object?)item.BlobETag ?? DBNull.Value);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}

public sealed record BackfillResult(
    int Examined,
    int Upserted,
    int Skipped);