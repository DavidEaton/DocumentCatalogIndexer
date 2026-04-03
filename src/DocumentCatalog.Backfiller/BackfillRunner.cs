using DocumentCatalogBackfiller;
using DocumentCatalogIndexer.Functions.Models;
using Microsoft.Extensions.Logging;

public sealed class BackfillRunner(
    ICatalogBackfillService backfillService,
    ILogger<BackfillRunner> logger)
{
    private readonly ICatalogBackfillService _backfillService = backfillService;
    private readonly ILogger<BackfillRunner> _logger = logger;

    public async Task<int> RunAsync(string[] args)
    {
        var options = ParseArgs(args);

        if (options.ShowHelp)
        {
            PrintUsage();
            return 0;
        }

        var companies = options.Company is null
            ? Enum.GetValues<Company>()
            : [options.Company.Value];

        foreach (var company in companies)
        {
            _logger.LogInformation("Starting backfill for company {Company}.", company);

            try
            {
                var result = await _backfillService.BackfillCompanyAsync(
                    company,
                    options.DryRun,
                    options.Limit,
                    CancellationToken.None);

                _logger.LogInformation(
                    "Completed backfill for company {Company}. Examined={Examined} Upserted={Upserted} Skipped={Skipped}",
                    company,
                    result.Examined,
                    result.Upserted,
                    result.Skipped);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Backfill failed for company {Company}.", company);
                return 1;
            }
        }

        return 0;
    }

    private static BackfillOptions ParseArgs(string[] args)
    {
        Company? company = null;
        var dryRun = false;
        int? limit = null;
        var showHelp = false;

        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i].ToLowerInvariant())
            {
                case "--help":
                case "-h":
                    showHelp = true;
                    break;

                case "--dry-run":
                    dryRun = true;
                    break;

                case "--company":
                    if (i + 1 >= args.Length)
                        throw new ArgumentException("--company requires a value.");

                    if (!Enum.TryParse<Company>(args[++i], ignoreCase: true, out var parsed))
                        throw new ArgumentException($"Invalid company '{args[i]}'.");

                    company = parsed;
                    break;

                case "--limit":
                    if (i + 1 >= args.Length)
                        throw new ArgumentException("--limit requires a value.");

                    if (!int.TryParse(args[++i], out var parsedLimit) || parsedLimit <= 0)
                        throw new ArgumentException($"Invalid limit '{args[i]}'.");

                    limit = parsedLimit;
                    break;

                default:
                    throw new ArgumentException($"Unknown argument '{args[i]}'.");
            }
        }

        return new BackfillOptions(company, dryRun, limit, showHelp);
    }

    private static void PrintUsage()
    {
        Console.WriteLine("""
            Usage:
              dotnet run -- [--company CII|CSI|DSI|DSN] [--dry-run] [--limit N]

            Examples:
              dotnet run -- --company CII
              dotnet run -- --company DSI --dry-run
              dotnet run -- --limit 100
            """);
    }

    private sealed record BackfillOptions(
        Company? Company,
        bool DryRun,
        int? Limit,
        bool ShowHelp);
}