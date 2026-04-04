using Azure.Messaging.EventGrid;
using DocumentCatalog.IndexerFunctions.Models;

namespace DocumentCatalog.IndexerFunctions.Routing;

public interface ICompanyRoutingService
{
    RoutedBlobEvent Resolve(EventGridEvent e);
}