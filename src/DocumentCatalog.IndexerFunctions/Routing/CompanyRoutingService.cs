using System.Text.Json;
using Azure.Messaging.EventGrid;
using DocumentCatalog.IndexerFunctions.Models;

namespace DocumentCatalog.IndexerFunctions.Routing;

public sealed class CompanyRoutingService : ICompanyRoutingService
{
    private const string CONTAINERNAME = "hrdocs";

    public RoutedBlobEvent Resolve(EventGridEvent e)
    {
        using var doc = JsonDocument.Parse(e.Data.ToString());
        var url = doc.RootElement.GetProperty("url").GetString()
            ?? throw new InvalidOperationException("Blob event is missing data.url.");

        var uri = new Uri(url);
        var accountName = uri.Host.Split('.')[0];
        var segments = uri.AbsolutePath.Trim('/').Split('/', 2);

        if (segments.Length < 2)
            throw new InvalidOperationException($"Unexpected blob path: {uri.AbsolutePath}");

        var container = segments[0];
        var blobName = segments[1];
        var company = ResolveCompanyKey(accountName, container);

        return new RoutedBlobEvent(company, accountName, container, blobName);
    }

    private static string ResolveCompanyKey(string accountName, string container)
    {
        var normalizedAccountName = accountName.ToLowerInvariant();
        var normalizedContainer = container.ToLowerInvariant();

        return (normalizedAccountName, normalizedContainer) switch
        {
            ("cii", CONTAINERNAME) => nameof(Company.CII),
            ("csii", CONTAINERNAME) => nameof(Company.CSI),
            ("dsii", CONTAINERNAME) => nameof(Company.DSI),
            ("dsni", CONTAINERNAME) => nameof(Company.DSN),

            _ => throw new InvalidOperationException(
                $"No company mapping exists for account '{accountName}' and container '{container}'.")
        };
    }
}
