using DocumentCatalog.Backfiller;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddLogging(logging =>
{
    logging.ClearProviders();
    logging.AddSimpleConsole(options =>
    {
        options.SingleLine = true;
        options.TimestampFormat = "yyyy-MM-dd HH:mm:ss.fff zzz ";
        options.IncludeScopes = true;
    });
});

builder.Services.AddSingleton<IBlobClientFactory, BlobClientFactory>();
builder.Services.AddSingleton<ISqlConnectionStringFactory, SqlConnectionStringFactory>();
builder.Services.AddSingleton<ICatalogBackfillService, CatalogBackfillService>();
builder.Services.AddSingleton<BackfillRunner>();

var host = builder.Build();

var runner = host.Services.GetRequiredService<BackfillRunner>();
return await runner.RunAsync(args);