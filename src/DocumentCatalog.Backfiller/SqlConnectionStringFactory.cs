using DocumentCatalog.IndexerFunctions.Models;

namespace DocumentCatalog.Backfiller;

public interface ISqlConnectionStringFactory
{
    string Create(Company company);
}

public sealed class SqlConnectionStringFactory : ISqlConnectionStringFactory
{
    public string Create(Company company)
    {
        var server = Environment.GetEnvironmentVariable("SQL_SERVER");
        var database = company switch
        {
            Company.CII => Environment.GetEnvironmentVariable("CII_SQL_DATABASE"),
            Company.CSI => Environment.GetEnvironmentVariable("CSI_SQL_DATABASE"),
            Company.DSI => Environment.GetEnvironmentVariable("DSI_SQL_DATABASE"),
            Company.DSN => Environment.GetEnvironmentVariable("DSN_SQL_DATABASE"),

            _ => throw new InvalidOperationException($"Unsupported company '{company}'.")
        };

        return string.IsNullOrWhiteSpace(server) || string.IsNullOrWhiteSpace(database)
            ? throw new InvalidOperationException($"Missing SQL server/database settings for company '{company}'.")
            : $"Server=tcp:{server},1433;Database={database};Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Managed Identity;";
    }
}