using System.Data;
using DocumentCatalog.Shared;
using DocumentCatalogIndexer.Functions.Models;
using Microsoft.Data.SqlClient;

namespace DocumentCatalogIndexer.Functions.Sql;

public sealed class BlobCatalogCommandService : IBlobCatalogCommandService
{
    public async Task UpsertAsync(BlobCatalogItem item, CancellationToken cancellationToken)
    {
        var connectionString = GetSqlConnectionString(item.Company);

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

    public async Task MarkDeletedAsync(Company company, string blobName, CancellationToken cancellationToken)
    {
        var connectionString = GetSqlConnectionString(company);
        var blobNameHash = DocumentBlobParser.ComputeBlobNameHash(blobName);

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var command = new SqlCommand(
            "Common.usp_EmployeeDocumentCatalog_MarkDeletedByBlobName",
            connection)
        {
            CommandType = CommandType.StoredProcedure,
            CommandTimeout = 60
        };

        command.Parameters.AddWithValue("@BlobName", blobName);
        command.Parameters.AddWithValue("@BlobNameHash", blobNameHash);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static string GetSqlConnectionString(Company company) =>
        Environment.GetEnvironmentVariable($"{company}_SQL_CONNECTION")
        ?? throw new InvalidOperationException($"Missing SQL connection string for {company}.");
}