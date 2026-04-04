using Azure.Identity;
using Azure.Storage.Blobs;
using DocumentCatalog.IndexerFunctions.Models;

namespace DocumentCatalogBackfiller
{
    public interface IBlobClientFactory
    {
        BlobContainerClient CreateContainerClient(Company company, string containerName);
    }

    public sealed class BlobClientFactory : IBlobClientFactory
    {
        private static readonly DefaultAzureCredential Credential = new();

        public BlobContainerClient CreateContainerClient(Company company, string containerName)
        {
            var accountUrl = company switch
            {
                Company.CII => Environment.GetEnvironmentVariable("CII_BLOB_ACCOUNT_URL"),
                Company.CSI => Environment.GetEnvironmentVariable("CSI_BLOB_ACCOUNT_URL"),
                Company.DSI => Environment.GetEnvironmentVariable("DSI_BLOB_ACCOUNT_URL"),
                Company.DSN => Environment.GetEnvironmentVariable("DSN_BLOB_ACCOUNT_URL"),
                _ => null
            };

            if (string.IsNullOrWhiteSpace(accountUrl))
                throw new InvalidOperationException($"Missing blob account URL for company '{company}'.");

            var serviceClient = new BlobServiceClient(new Uri(accountUrl), Credential);
            return serviceClient.GetBlobContainerClient(containerName);
        }
    }
}