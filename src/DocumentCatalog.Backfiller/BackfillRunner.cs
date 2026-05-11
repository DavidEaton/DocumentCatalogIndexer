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

            var companies = new List<string>();
            var runId = Guid.NewGuid().ToString("n");
            var buildMarker = Environment.GetEnvironmentVariable("BUILD_MARKER") ?? "local-dev";

            using var runScope = _logger.BeginScope(new Dictionary<string, object>
            {
                ["RunId"] = runId,
                ["DryRun"] = options.DryRun,
                ["BuildMarker"] = buildMarker
            });

            _logger.LogInformation(
                "Backfill run starting. BuildMarker={BuildMarker} RunId={RunId} Args={Args} Companies={Companies} DryRun={DryRun}",
                buildMarker,
                runId,
                string.Join(" ", args),
                string.Join(",", companies),
                options.DryRun);

            foreach (var company in companies)
            {

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
                        CancellationToken.None);

                    _logger.LogInformation(
                        "Completed backfill for company {Company}. Examined={Examined} Candidates={Candidates} Upserted={Upserted} SkippedInvalidName={SkippedInvalidName} SqlFailures={SqlFailures}",
                        company,
                        result.Examined,
                        result.Candidates,
                        result.Upserted,
                        result.SkippedInvalidName,
                        result.SqlFailures);
                }
                catch (Exception ex)
                {
                    _logger.LogError(
                        ex,
                        "Backfill failed for company {Company}. Cause: {ex.Message}.",
                        company,
                        ex.Message);

                    return 1;
                }
            }

            _logger.LogInformation("Backfill run completed successfully. RunId={RunId}", runId);
            return 0;
        }

        private static BackfillOptions ParseArgs(string[] args)
        {
            var company = Environment.GetEnvironmentVariable("COMPANY");
            var dryRunValue = Environment.GetEnvironmentVariable("DRY_RUN");
            var dryRun = !bool.TryParse(dryRunValue, out var parsedDryRun)
                || parsedDryRun;
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

                        var companyArg = args[++i];

                        if (int.TryParse(companyArg, out _))
                            throw new ArgumentException($"Invalid company '{companyArg}'.");

                        if (!Enum.TryParse<Company>(companyArg, ignoreCase: true, out var parsed) ||
                            !Enum.IsDefined(parsed))
                        {
                            throw new ArgumentException($"Invalid company '{companyArg}'.");
                        }

                        company = parsed.ToString();
                        break;

                    default:
                        throw new ArgumentException($"Unknown argument '{args[i]}'.");
                }
            }

            return new BackfillOptions(company, dryRun, showHelp);
        }

        private static void PrintUsage()
        {
            Console.WriteLine("""
            Usage:
              dotnet run -- [--company CII|CSI|DSI|DSN] [--dry-run]

            Examples:
              dotnet run -- --company CII
              dotnet run -- --company DSI --dry-run
            """);
        }

        private sealed record BackfillOptions(
            string? Company,
            bool DryRun,
            bool ShowHelp);
    }
}
