using Azure.Messaging.EventGrid;
using DocumentCatalog.IndexerFunctions.Routing;
using DocumentCatalog.IndexerFunctions.Sql;
using DocumentCatalog.IndexerFunctions.Storage;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace DocumentCatalog.IndexerFunctions;

public sealed class BlobCatalogEventFunction(
    ICompanyRoutingService routingService,
    IBlobMetadataReader blobMetadataReader,
    IBlobCatalogCommandService commandService,
    ILogger<BlobCatalogEventFunction> logger)
{
    private readonly ICompanyRoutingService _routingService = routingService;
    private readonly IBlobMetadataReader _blobMetadataReader = blobMetadataReader;
    private readonly IBlobCatalogCommandService _commandService = commandService;
    private readonly ILogger<BlobCatalogEventFunction> _logger = logger;

    [Function("BlobCatalogEventFunction")]
    public async Task Run(
        [EventGridTrigger] EventGridEvent eventGridEvent,
        CancellationToken cancellationToken)
    {
        var routed = _routingService.Resolve(eventGridEvent);

        _logger.LogInformation(
            "Received blob event {EventType} for {Company}, blob {BlobName}.",
            eventGridEvent.EventType,
            routed.Company,
            routed.BlobName);

        if (eventGridEvent.EventType == "Microsoft.Storage.BlobDeleted")
        {
            await _commandService.MarkDeletedAsync(
                routed.Company,
                routed.BlobName,
                cancellationToken);

            return;
        }

        if (eventGridEvent.EventType != "Microsoft.Storage.BlobCreated")
        {
            _logger.LogInformation(
                "Ignoring unsupported event type {EventType}.",
                eventGridEvent.EventType);

            return;
        }

        var item = await _blobMetadataReader.GetBlobInfoAsync(
            routed.Company,
            routed.ContainerName,
            routed.BlobName,
            cancellationToken);

        if (!item.IsCatalogCandidate)
        {
            _logger.LogInformation(
                "Skipping blob {BlobName} because it does not match the catalog naming convention.",
                routed.BlobName);
            return;
        }

        await _commandService.UpsertAsync(item, cancellationToken);
    }
}