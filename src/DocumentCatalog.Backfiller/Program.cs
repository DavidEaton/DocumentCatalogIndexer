using DocumentCatalog.Backfiller;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;

var builder = Host.CreateApplicationBuilder(args);

var logPath = Environment.GetEnvironmentVariable("BACKFILL_LOG_PATH")
    ?? "/mnt/backfiller-logs/documentcatalog/backfiller/log-.txt";

Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);

Log.Logger = new LoggerConfiguration()
    .Enrich.FromLogContext()
    .MinimumLevel.Debug()
    .WriteTo.Console(
        outputTemplate: "{Timestamp:yyyy-MM-dd hh:mm:ss tt zzz} [{Level:u3}] [{SourceContext}] {Message:lj} {NewLine}{Exception}")
    .WriteTo.File(
        path: logPath,
        rollingInterval: RollingInterval.Day,
        retainedFileCountLimit: 14,
        shared: true,
        outputTemplate: "{Timestamp:yyyy-MM-dd hh:mm:ss tt zzz} [{Level:u3}] [{SourceContext}] {Message:lj} {NewLine}{Exception}")
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
finally
{
    await Log.CloseAndFlushAsync();
}
