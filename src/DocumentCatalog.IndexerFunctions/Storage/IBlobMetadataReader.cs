using DocumentCatalog.IndexerFunctions.Models;

namespace DocumentCatalog.IndexerFunctions.Storage;

public interface IBlobMetadataReader
{
    Task<BlobCatalogItem> GetBlobInfoAsync(
        string company,
        string containerName,
        string blobName,
        CancellationToken cancellationToken);
}