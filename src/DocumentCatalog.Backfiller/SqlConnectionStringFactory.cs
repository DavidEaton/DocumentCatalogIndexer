using DocumentCatalog.IndexerFunctions.Models;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;

namespace DocumentCatalog.Backfiller;

public sealed class SqlConnectionStringFactory : ISqlConnectionStringFactory
{
    private readonly IHostEnvironment _hostEnvironment;
    private readonly IConfiguration _configuration;

    public SqlConnectionStringFactory(IHostEnvironment hostEnvironment, IConfiguration configuration)
    {
        _hostEnvironment = hostEnvironment;
        _configuration = configuration;
    }

    public string Create(Company company)
    {
        var server = GetServerName();
        var database = GetDatabaseName(company);

        return
            $"Server=tcp:{server},1433;" +
            $"Database={database};" +
            $"Encrypt=True;" +
            $"TrustServerCertificate=False;" +
            $"Authentication=Active Directory Managed Identity;";
    }

    public string GetServerName()
    {
        if (_hostEnvironment.IsDevelopment())
        {
            var secretServer = _configuration["CompanyConnections:ServerName"];
            if (!string.IsNullOrWhiteSpace(secretServer))
                return secretServer;
        }

        var server = Environment.GetEnvironmentVariable("SQL_SERVER");

        if (string.IsNullOrWhiteSpace(server))
            throw new InvalidOperationException("Missing SQL_SERVER environment variable.");

        return server;
    }

    public string GetDatabaseName(Company company)
    {
        if (_hostEnvironment.IsDevelopment())
        {
            var secretDatabase = GetSqlDatabaseName(company);
            if (!string.IsNullOrWhiteSpace(secretDatabase))
                return secretDatabase;
        }

        var database = company switch
        {
            Company.CII => Environment.GetEnvironmentVariable("CII_SQL_DATABASE"),
            Company.CSI => Environment.GetEnvironmentVariable("CSI_SQL_DATABASE"),
            Company.DSI => Environment.GetEnvironmentVariable("DSI_SQL_DATABASE"),
            Company.DSN => Environment.GetEnvironmentVariable("DSN_SQL_DATABASE"),
            _ => throw new InvalidOperationException($"Unsupported company '{company}'.")
        };

        if (string.IsNullOrWhiteSpace(database))
            throw new InvalidOperationException($"Missing SQL database setting for company '{company}'.");

        return database;
    }

    private string? GetSqlDatabaseName(Company company)
    {
        var companyCode = company.ToString();
        var key = $"CompanyConnections:Companies:{companyCode}:SqlDatabaseName";
        return _configuration[key];
    }
}
