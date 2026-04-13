using System.Diagnostics;
using DocumentCatalog.IndexerFunctions.Models;
using Microsoft.Extensions.Logging;

namespace DocumentCatalog.Backfiller
{
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

            var runId = Guid.NewGuid().ToString("n");
            var buildMarker = Environment.GetEnvironmentVariable("BUILD_MARKER") ?? "local-dev";

            using var runScope = _logger.BeginScope(new Dictionary<string, object>
            {
                ["RunId"] = runId,
                ["DryRun"] = options.DryRun,
                ["Limit"] = options.Limit?.ToString() ?? "(none)",
                ["BuildMarker"] = buildMarker
            });

            _logger.LogInformation(
                "Backfill run starting. BuildMarker={BuildMarker} RunId={RunId} Args={Args} Companies={Companies} DryRun={DryRun} Limit={Limit}",
                buildMarker,
                runId,
                string.Join(" ", args),
                string.Join(",", companies),
                options.DryRun,
                options.Limit);

            foreach (var company in companies)
            {
                var stopwatch = Stopwatch.StartNew();

                using var companyScope = _logger.BeginScope(new Dictionary<string, object>
                {
                    ["Company"] = company.ToString()
                });

                _logger.LogInformation("Starting backfill for company {Company}.", company);

                try
                {
                    var result = await _backfillService.BackfillCompanyAsync(
                        company,
                        options.DryRun,
                        options.Limit,
                        CancellationToken.None);

                    stopwatch.Stop();

                    _logger.LogInformation(
                        "Completed backfill for company {Company}. DurationMs={DurationMs} Examined={Examined} Candidates={Candidates} Upserted={Upserted} SkippedInvalidName={SkippedInvalidName} SqlFailures={SqlFailures}",
                        company,
                        stopwatch.ElapsedMilliseconds,
                        result.Examined,
                        result.Candidates,
                        result.Upserted,
                        result.SkippedInvalidName,
                        result.SqlFailures);
                }
                catch (Exception ex)
                {
                    stopwatch.Stop();

                    _logger.LogError(
                        ex,
                        "Backfill failed for company {Company} after {DurationMs} ms.",
                        company,
                        stopwatch.ElapsedMilliseconds);

                    return 1;
                }
            }

            _logger.LogInformation("Backfill run completed successfully. RunId={RunId}", runId);
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
}
