using DocumentCatalog.Backfiller;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;

var builder = Host.CreateApplicationBuilder(args);

var configuredLogPath = builder.Environment.IsDevelopment()
    ? builder.Configuration["LogPath"]
    : Environment.GetEnvironmentVariable("BACKFILL_LOG_PATH");

var requestedLogPath = string.IsNullOrWhiteSpace(configuredLogPath)
    ? "/tmp/documentcatalog-backfiller/log-.txt"
    : configuredLogPath;

string effectiveLogPath;

try
{
    EnsureLogDirectoryExists(requestedLogPath);
    effectiveLogPath = requestedLogPath;
}
catch (Exception ex)
{
    var fallbackLogPath = "/tmp/documentcatalog-backfiller/log-.txt";
    EnsureLogDirectoryExists(fallbackLogPath);
    effectiveLogPath = fallbackLogPath;

    Console.Error.WriteLine($"[Backfiller] Failed to initialize requested BACKFILL_LOG_PATH '{requestedLogPath}'. Falling back to '{fallbackLogPath}'. Error: {ex.Message}");
}

Console.WriteLine($"[Backfiller] Effective log path: {effectiveLogPath}");

Log.Logger = new LoggerConfiguration()
    .Enrich.FromLogContext()
    .MinimumLevel.Debug()
    .WriteTo.Console(
        outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {SourceContext} {Message:lj} {Properties:j}{NewLine}{Exception}")
    .WriteTo.File(
        path: effectiveLogPath,
        rollingInterval: RollingInterval.Day,
        retainedFileCountLimit: 14,
        shared: true,
        flushToDiskInterval: TimeSpan.FromSeconds(1),
        outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {SourceContext} {Message:lj} {Properties:j}{NewLine}{Exception}")
    .CreateLogger();

builder.Services.AddSerilog();

builder.Services.AddSingleton<IBlobClientFactory, BlobClientFactory>();
builder.Services.AddSingleton<ISqlConnectionStringFactory, SqlConnectionStringFactory>();
builder.Services.AddSingleton<ICatalogBackfillService, CatalogBackfillService>();
builder.Services.AddSingleton<BackfillRunner>();

var host = builder.Build();

try
{
    var runner = host.Services.GetRequiredService<BackfillRunner>();
    return await runner.RunAsync(args);
}
catch (Exception ex)
{
    Log.Fatal(ex, "Backfiller terminated unexpectedly.");
    Console.Error.WriteLine($"[Backfiller] Fatal error: {ex.Message}");
    return 1;
}
finally
{
    await Log.CloseAndFlushAsync();
}

static void EnsureLogDirectoryExists(string logPath)
{
    var directory = Path.GetDirectoryName(logPath);

    if (string.IsNullOrWhiteSpace(directory))
    {
        throw new InvalidOperationException($"Log path '{logPath}' must include a directory.");
    }

    Directory.CreateDirectory(directory);
}
