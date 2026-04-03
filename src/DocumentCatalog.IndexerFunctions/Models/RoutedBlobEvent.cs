namespace DocumentCatalogIndexer.Functions.Models;

public sealed record RoutedBlobEvent(
    Company Company,
    string StorageAccountName,
    string ContainerName,
    string BlobName);