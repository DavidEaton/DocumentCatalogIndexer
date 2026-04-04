using DocumentCatalog.IndexerFunctions.Models;

namespace DocumentCatalog.IndexerFunctions.Sql;

public interface IBlobCatalogCommandService
{
    Task UpsertAsync(BlobCatalogItem item, CancellationToken cancellationToken);
    Task MarkDeletedAsync(Company company, string blobName, CancellationToken cancellationToken);
}