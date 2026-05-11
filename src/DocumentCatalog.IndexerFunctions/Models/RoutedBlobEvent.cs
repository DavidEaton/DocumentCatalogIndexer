namespace DocumentCatalog.IndexerFunctions.Models;

public sealed record RoutedBlobEvent(
    string Company,
    string StorageAccountName,
    string ContainerName,
    string BlobName);