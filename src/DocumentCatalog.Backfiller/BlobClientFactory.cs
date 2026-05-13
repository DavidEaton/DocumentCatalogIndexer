using Azure.Core;
using Azure.Identity;
using Azure.Storage.Blobs;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using System.Data.Common;

namespace DocumentCatalog.Backfiller
{

    public sealed class BlobClientFactory : IBlobClientFactory
    {
        private static readonly TokenCredential Credential = CreateCredential();
        private static readonly string CredentialMode = DetermineCredentialMode();
        private readonly IHostEnvironment _hostEnvironment;
        private readonly IConfiguration _configuration;

        public BlobClientFactory(IHostEnvironment hostEnvironment, IConfiguration configuration)
        {
            _hostEnvironment = hostEnvironment;
            _configuration = configuration;
        }

        public BlobContainerClient CreateContainerClient(string company, string containerName)
        {
            if (_hostEnvironment.IsDevelopment())
            {
                var secretConnectionString = GetBlobStorageConnectionString(company);
                if (!string.IsNullOrWhiteSpace(secretConnectionString))
                {
                    var connectionStringServiceClient = new BlobServiceClient(secretConnectionString);
                    return connectionStringServiceClient.GetBlobContainerClient(containerName);
                }
            }

            var accountUrl = GetAccountUrl(company);
            var serviceClient = new BlobServiceClient(new Uri(accountUrl), Credential);
            return serviceClient.GetBlobContainerClient(containerName);
        }

        public string GetAccountUrl(string company)
        {
            if (_hostEnvironment.IsDevelopment())
            {
                var secretConnectionString = GetBlobStorageConnectionString(company);
                if (!string.IsNullOrWhiteSpace(secretConnectionString))
                    return BuildAccountUrlFromConnectionString(secretConnectionString, company);
            }

            var accountUrl = company switch
            {
                "CII" => Environment.GetEnvironmentVariable("CII_BLOB_ACCOUNT_URL"),
                "CSI" => Environment.GetEnvironmentVariable("CSI_BLOB_ACCOUNT_URL"),
                "DSI" => Environment.GetEnvironmentVariable("DSI_BLOB_ACCOUNT_URL"),
                "DSN" => Environment.GetEnvironmentVariable("DSN_BLOB_ACCOUNT_URL"),
                _ => null
            };

            if (string.IsNullOrWhiteSpace(accountUrl))
                throw new InvalidOperationException($"Missing blob account URL for company '{company}'.");

            return accountUrl;
        }

        private string? GetBlobStorageConnectionString(string company)
        {
            var companyCode = company.ToString();
            var key = $"CompanyConnections:Companies:{companyCode}:BlobStorageConnectionString";
            return _configuration[key];
        }

        private static string BuildAccountUrlFromConnectionString(string connectionString, string company)
        {
            var builder = new DbConnectionStringBuilder { ConnectionString = connectionString };

            if (!builder.TryGetValue("AccountName", out var accountNameValue) ||
                string.IsNullOrWhiteSpace(accountNameValue?.ToString()))
            {
                throw new InvalidOperationException($"Missing AccountName in blob storage connection string for company '{company}'.");
            }

            var accountName = accountNameValue.ToString();
            var endpointSuffix = builder.TryGetValue("EndpointSuffix", out var endpointSuffixValue) &&
                                 !string.IsNullOrWhiteSpace(endpointSuffixValue?.ToString())
                ? endpointSuffixValue.ToString()
                : "core.windows.net";

            return $"https://{accountName}.blob.{endpointSuffix}";
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
