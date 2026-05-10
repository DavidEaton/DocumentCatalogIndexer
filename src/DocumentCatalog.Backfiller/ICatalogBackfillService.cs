using DocumentCatalog.IndexerFunctions.Models;

namespace DocumentCatalog.Backfiller;

public interface ICatalogBackfillService
{
    Task<BackfillResult> BackfillCompanyAsync(
        Company company,
        bool dryRun,
        CancellationToken cancellationToken);
}
