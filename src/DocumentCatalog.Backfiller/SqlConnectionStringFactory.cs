using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;

namespace DocumentCatalog.Backfiller;

public sealed class SqlConnectionStringFactory(
    IHostEnvironment hostEnvironment,
    IConfiguration configuration) : ISqlConnectionStringFactory
{
    private readonly IHostEnvironment _hostEnvironment = hostEnvironment;
    private readonly IConfiguration _configuration = configuration;

    public string Create(string company)
    {
        if (_hostEnvironment.IsDevelopment())
        {
            var connectionString = _configuration[$"CompanyConnections:Companies:{company}:ConnectionString"];
            if (!string.IsNullOrWhiteSpace(connectionString))
            {
                return connectionString;
            }
        }

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
        var server = Environment.GetEnvironmentVariable("SQL_SERVER");
        if (string.IsNullOrWhiteSpace(server))
        {
            throw new InvalidOperationException("Missing SQL_SERVER environment variable.");
        }

        return server;
    }

    public string GetDatabaseName(string company)
    {
        var database = company switch
        {
            "CII" => Environment.GetEnvironmentVariable("CII_SQL_DATABASE"),
            "CSI" => Environment.GetEnvironmentVariable("CSI_SQL_DATABASE"),
            "DSI" => Environment.GetEnvironmentVariable("DSI_SQL_DATABASE"),
            "DSN" => Environment.GetEnvironmentVariable("DSN_SQL_DATABASE"),
            _ => throw new InvalidOperationException($"Unsupported company '{company}'.")
        };

        if (string.IsNullOrWhiteSpace(database))
            throw new InvalidOperationException($"Missing SQL database setting for company '{company}'.");

        return database;
    }
}
