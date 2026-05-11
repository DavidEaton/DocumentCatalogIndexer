using Azure.Storage.Blobs;

namespace DocumentCatalog.Backfiller
{
    public interface IBlobClientFactory
    {
        BlobContainerClient CreateContainerClient(string company, string containerName);
        string GetAccountUrl(string company);
        string GetCredentialMode();
    }
}
