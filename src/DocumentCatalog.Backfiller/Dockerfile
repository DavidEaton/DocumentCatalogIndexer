FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY . .
RUN dotnet restore ./src/DocumentCatalog.Backfiller/DocumentCatalog.Backfiller.csproj
RUN dotnet publish ./src/DocumentCatalog.Backfiller/DocumentCatalog.Backfiller.csproj -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/runtime:10.0
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "DocumentCatalog.Backfiller.dll"]