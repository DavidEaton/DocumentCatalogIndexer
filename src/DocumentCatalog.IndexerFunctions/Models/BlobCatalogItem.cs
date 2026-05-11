namespace DocumentCatalog.IndexerFunctions.Models
{
    public sealed record BlobCatalogItem(
        string Company,
        string BlobName,
        byte[] BlobNameHash,
        int EmployeeId,
        string DocumentTypeToken,
        string DocumentTypeDisplay,
        DateTimeOffset? UpdatedUtc,
        string? ContentType,
        string? BlobETag);
}
