create or alter procedure Common.usp_EmployeeDocumentCatalog_MarkDeletedByBlobName
    @BlobName     nvarchar(512),
    @BlobNameHash varbinary(32)
as
begin
    set nocount on;
    set xact_abort on;

    update Common.EmployeeDocumentCatalog
    set
        IsDeleted = 1,
        LastIndexedUtc = sysutcdatetime()
    where BlobNameHash = @BlobNameHash
      and BlobName = @BlobName;
end
go