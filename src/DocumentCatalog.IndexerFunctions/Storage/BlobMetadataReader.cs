using Azure.Storage.Blobs;
using DocumentCatalog.IndexerFunctions.Models;
using DocumentCatalog.Shared;

namespace DocumentCatalog.IndexerFunctions.Storage;

public sealed class BlobMetadataReader : IBlobMetadataReader
{
    public async Task<BlobCatalogItem> GetBlobInfoAsync(
        string company,
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
                properties.Value.LastModified,
                properties.Value.ContentType,
                properties.Value.ETag.ToString());
        }

        return new BlobCatalogItem(
            company,
            blobName,
            DocumentBlobParser.ComputeBlobNameHash(blobName),
            employeeId,
            documentTypeToken,
            DocumentBlobParser.HumanizeDocumentType(documentTypeToken),
            properties.Value.LastModified,
            properties.Value.ContentType,
            properties.Value.ETag.ToString());
    }
}