using Azure.Identity;
using Azure.Storage.Blobs;
using DocumentCatalog.IndexerFunctions.Models;

namespace DocumentCatalogBackfiller;

public interface ISqlConnectionStringFactory
{
    string Create(Company company);
}

public sealed class SqlConnectionStringFactory : ISqlConnectionStringFactory
{
    public string Create(Company company)
    {
        var (server, database) = company switch
        {
            Company.CII => (
                Environment.GetEnvironmentVariable("CII_SQL_SERVER"),
                Environment.GetEnvironmentVariable("CII_SQL_DATABASE")),

            Company.CSI => (
                Environment.GetEnvironmentVariable("CSI_SQL_SERVER"),
                Environment.GetEnvironmentVariable("CSI_SQL_DATABASE")),

            Company.DSI => (
                Environment.GetEnvironmentVariable("DSI_SQL_SERVER"),
                Environment.GetEnvironmentVariable("DSI_SQL_DATABASE")),

            Company.DSN => (
                Environment.GetEnvironmentVariable("DSN_SQL_SERVER"),
                Environment.GetEnvironmentVariable("DSN_SQL_DATABASE")),

            _ => throw new InvalidOperationException($"Unsupported company '{company}'.")
        };

        if (string.IsNullOrWhiteSpace(server) || string.IsNullOrWhiteSpace(database))
            throw new InvalidOperationException($"Missing SQL server/database settings for company '{company}'.");

        return $"Server=tcp:{server},1433;Database={database};Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Managed Identity;";
    }
}