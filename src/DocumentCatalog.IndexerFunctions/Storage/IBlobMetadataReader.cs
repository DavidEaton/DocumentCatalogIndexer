using DocumentCatalogIndexer.Functions.Models;

namespace DocumentCatalogIndexer.Functions.Storage;

public interface IBlobMetadataReader
{
    Task<BlobCatalogItem> GetBlobInfoAsync(
        Company company,
        string containerName,
        string blobName,
        CancellationToken cancellationToken);
}