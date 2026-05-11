namespace DocumentCatalog.Backfiller;

public interface ISqlConnectionStringFactory
{
    string Create(string company);
    string GetServerName();
    string GetDatabaseName(string company);
}
