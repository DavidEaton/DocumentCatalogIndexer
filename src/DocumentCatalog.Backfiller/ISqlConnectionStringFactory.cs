using DocumentCatalog.IndexerFunctions.Models;

namespace DocumentCatalog.Backfiller;

public interface ISqlConnectionStringFactory
{
    string Create(Company company);
    string GetServerName();
    string GetDatabaseName(Company company);
}
