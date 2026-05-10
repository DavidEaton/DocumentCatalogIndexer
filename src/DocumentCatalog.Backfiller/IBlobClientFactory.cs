using Azure.Storage.Blobs;
using DocumentCatalog.IndexerFunctions.Models;

namespace DocumentCatalog.Backfiller
{
    public interface IBlobClientFactory
    {
        BlobContainerClient CreateContainerClient(Company company, string containerName);
        string GetAccountUrl(Company company);
        string GetCredentialMode();
    }
}
