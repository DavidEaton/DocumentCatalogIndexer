-- In each company database, create a user for the function’s managed identity and grant execute on the procedures
create user [your-function-app-name] from external provider;
go

grant execute on object::Common.usp_EmployeeDocumentCatalog_UpsertFromBlobEvent to [your-function-app-name];
grant execute on object::Common.usp_EmployeeDocumentCatalog_MarkDeletedByBlobName to [your-function-app-name];
grant execute on object::Common.usp_EmployeeDocumentCatalog_Search to [your-function-app-name];
go