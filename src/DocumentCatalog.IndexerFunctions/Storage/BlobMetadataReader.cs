using Azure.Storage.Blobs;
using DocumentCatalog.Shared;
using DocumentCatalogIndexer.Functions.Models;

namespace DocumentCatalogIndexer.Functions.Storage;

public sealed class BlobMetadataReader : IBlobMetadataReader
{
    public async Task<BlobCatalogItem> GetBlobInfoAsync(
        Company company,
        string containerName,
        string blobName,
        CancellationToken cancellationToken)
    {
        var connectionString = Environment.GetEnvironmentVariable($"{company}_BLOB_CONNECTION")
            ?? throw new InvalidOperationException($"Missing blob connection string for {company}.");

        var container = new BlobContainerClient(connectionString, containerName);
        var blobClient = container.GetBlobClient(blobName);

        var properties = await blobClient.GetPropertiesAsync(cancellationToken: cancellationToken);

        if (!DocumentBlobParser.TryParseEmployeeDocumentBlobName(
                blobName,
                out var employeeId,
                out var documentTypeToken))
        {
            return new BlobCatalogItem(
                company,
                blobName,
                DocumentBlobParser.ComputeBlobNameHash(blobName),
                0,
                string.Empty,
                string.Empty,
                null,
                properties.Value.LastModified,
                properties.Value.ContentType,
                properties.Value.ETag.ToString(),
                false);
        }

        return new BlobCatalogItem(
            company,
            blobName,
            DocumentBlobParser.ComputeBlobNameHash(blobName),
            employeeId,
            documentTypeToken,
            DocumentBlobParser.HumanizeDocumentType(documentTypeToken),
            properties.Value.LastModified,
            properties.Value.LastModified,
            properties.Value.ContentType,
            properties.Value.ETag.ToString(),
            true);
    }
}