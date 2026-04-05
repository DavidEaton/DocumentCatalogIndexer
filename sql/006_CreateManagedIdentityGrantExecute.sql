-- In each company database, create a user for the function’s managed identity 
-- and grant SQL access to the DocumentCatalogIndexer Function Apps managed identity
create user DocumentCatalogIndexer from external provider;
go

grant execute on object::Common.usp_EmployeeDocumentCatalog_UpsertFromBlobEvent to [DocumentCatalogIndexer];
grant execute on object::Common.usp_EmployeeDocumentCatalog_MarkDeletedByBlobName to [DocumentCatalogIndexer];
grant execute on object::Common.usp_EmployeeDocumentCatalog_Search to [DocumentCatalogIndexer];
go


create user [documentcatalog-backfiller] from external provider;
go

grant execute on object::Common.usp_EmployeeDocumentCatalog_UpsertFromBlobEvent to [documentcatalog-backfiller];
go