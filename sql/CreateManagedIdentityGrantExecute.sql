-- In each company database, create a user for the function’s managed identity 
-- and grant SQL access to the DocumentCatalogIndexer Function Apps managed identity
set nocount on;
set xact_abort on;

if object_id(N'[Common].[usp_EmployeeDocumentCatalog_UpsertFromBlobEvent]', N'P') is null
    throw 51000, N'Required procedure [Common].[usp_EmployeeDocumentCatalog_UpsertFromBlobEvent] is missing.', 1;

if object_id(N'[Common].[usp_EmployeeDocumentCatalog_MarkDeletedByBlobName]', N'P') is null
    throw 51001, N'Required procedure [Common].[usp_EmployeeDocumentCatalog_MarkDeletedByBlobName] is missing.', 1;

if object_id(N'[Common].[usp_EmployeeDocumentCatalog_Search]', N'P') is null
    throw 51002, N'Required procedure [Common].[usp_EmployeeDocumentCatalog_Search] is missing.', 1;

if not exists
(
    select 1
    from sys.database_principals
    where name = N'DocumentCatalogIndexer'
)
begin
    create user [DocumentCatalogIndexer] from external provider;
end;

if not exists
(
    select 1
    from sys.database_principals
    where name = N'documentcatalog-backfiller'
)
begin
    create user [documentcatalog-backfiller] from external provider;
end;

grant execute on object::[Common].[usp_EmployeeDocumentCatalog_UpsertFromBlobEvent]
    to [DocumentCatalogIndexer];

grant execute on object::[Common].[usp_EmployeeDocumentCatalog_MarkDeletedByBlobName]
    to [DocumentCatalogIndexer];

grant execute on object::[Common].[usp_EmployeeDocumentCatalog_Search]
    to [DocumentCatalogIndexer];

grant execute on object::[Common].[usp_EmployeeDocumentCatalog_UpsertFromBlobEvent]
    to [documentcatalog-backfiller];