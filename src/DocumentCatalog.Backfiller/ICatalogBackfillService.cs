namespace DocumentCatalog.Backfiller;

public interface ICatalogBackfillService
{
    Task<BackfillResult> BackfillCompanyAsync(
        string company,
        bool dryRun,
        CancellationToken cancellationToken);
}
