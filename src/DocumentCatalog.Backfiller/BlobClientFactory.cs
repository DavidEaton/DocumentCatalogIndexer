using Azure.Core;
using Azure.Identity;
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

    public sealed class BlobClientFactory : IBlobClientFactory
    {
        private static readonly TokenCredential Credential = CreateCredential();
        private static readonly string CredentialMode = DetermineCredentialMode();

        public BlobContainerClient CreateContainerClient(Company company, string containerName)
        {
            var accountUrl = GetAccountUrl(company);
            var serviceClient = new BlobServiceClient(new Uri(accountUrl), Credential);
            return serviceClient.GetBlobContainerClient(containerName);
        }

        public string GetAccountUrl(Company company)
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

            return accountUrl;
        }

        public string GetCredentialMode() => CredentialMode;

        private static string DetermineCredentialMode()
        {
            var azureClientId = Environment.GetEnvironmentVariable("AZURE_CLIENT_ID");
            if (!string.IsNullOrWhiteSpace(azureClientId) && HasManagedIdentityEndpoint())
                return $"ManagedIdentityCredential(clientId={azureClientId})";

            if (HasManagedIdentityEndpoint())
                return "ManagedIdentityCredential(system-assigned)";

            return "ChainedTokenCredential(AzureCliCredential, VisualStudioCredential)";
        }

        private static TokenCredential CreateCredential()
        {
            var azureClientId = Environment.GetEnvironmentVariable("AZURE_CLIENT_ID");
            if (!string.IsNullOrWhiteSpace(azureClientId) && HasManagedIdentityEndpoint())
            {
                var id = ManagedIdentityId.FromUserAssignedClientId(azureClientId);
                return new ManagedIdentityCredential(id);
            }

            if (HasManagedIdentityEndpoint())
                return new ManagedIdentityCredential(new ManagedIdentityCredentialOptions());

            return new ChainedTokenCredential(
                new AzureCliCredential(),
                new VisualStudioCredential());
        }

        private static bool HasManagedIdentityEndpoint() =>
            !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("IDENTITY_ENDPOINT")) ||
            !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("MSI_ENDPOINT"));
    }
}
