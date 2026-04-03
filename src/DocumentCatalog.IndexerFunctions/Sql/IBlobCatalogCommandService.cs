using DocumentCatalogIndexer.Functions.Models;

namespace DocumentCatalogIndexer.Functions.Sql;

public interface IBlobCatalogCommandService
{
    Task UpsertAsync(BlobCatalogItem item, CancellationToken cancellationToken);
    Task MarkDeletedAsync(Company company, string blobName, CancellationToken cancellationToken);
}