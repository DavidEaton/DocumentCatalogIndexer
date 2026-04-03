using DocumentCatalogIndexer.Functions.Routing;
using DocumentCatalogIndexer.Functions.Sql;
using DocumentCatalogIndexer.Functions.Storage;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace DocumentCatalogIndexer.Functions
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var builder = FunctionsApplication.CreateBuilder(args);

            builder.Services.AddApplicationInsightsTelemetryWorkerService();
            builder.Services.ConfigureFunctionsApplicationInsights();

            builder.Services.AddSingleton<ICompanyRoutingService, CompanyRoutingService>();
            builder.Services.AddSingleton<IBlobMetadataReader, BlobMetadataReader>();
            builder.Services.AddSingleton<IBlobCatalogCommandService, BlobCatalogCommandService>();

            builder.Build().Run();
        }
    }
}