namespace DocumentCatalog.IndexerFunctions.Models
{
    public sealed record BlobCatalogItem(
        Company Company,
        string BlobName,
        byte[] BlobNameHash,
        int EmployeeId,
        string DocumentTypeToken,
        string DocumentTypeDisplay,
        DateTimeOffset? UpdatedUtc,
        DateTimeOffset? BlobLastModifiedUtc,
        string? ContentType,
        string? BlobETag,
        bool IsCatalogCandidate);
}