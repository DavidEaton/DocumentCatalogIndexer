namespace DocumentCatalog.IndexerFunctions.Models;

public sealed record RoutedBlobEvent(
    Company Company,
    string StorageAccountName,
    string ContainerName,
    string BlobName);