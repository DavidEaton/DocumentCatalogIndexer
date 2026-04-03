using Azure.Messaging.EventGrid;
using DocumentCatalogIndexer.Functions.Models;

namespace DocumentCatalogIndexer.Functions.Routing;

public interface ICompanyRoutingService
{
    RoutedBlobEvent Resolve(EventGridEvent e);
}