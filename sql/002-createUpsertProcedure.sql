-- Run in 
-- CII database CiiSql ✓
-- CSI database CsiSql 
-- DSI database DsiSql
-- DSN database DsnSql

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Replaces Common.usp_EmployeeDocumentCatalog_UpsertFromBlobEvent
create or alter procedure HR.EmployeeDocumentCatalogUpsertFromBlobEvent
    @BlobName            nvarchar(512),
    @BlobNameHash        varbinary(32),
    @EmployeeId          int,
    @DocumentTypeToken   nvarchar(200),
    @DocumentTypeDisplay nvarchar(200),
    @UpdatedUtc          datetimeoffset(7) = null,
    @ContentType         nvarchar(200) = null,
    @BlobETag            nvarchar(128) = null
as
begin
    set nocount on;
    set xact_abort on;

    update HR.EmployeeDocumentCatalog
    set
        EmployeeId = @EmployeeId,
        DocumentTypeToken = @DocumentTypeToken,
        DocumentTypeDisplay = @DocumentTypeDisplay,
        UpdatedUtc = @UpdatedUtc,
        ContentType = @ContentType,
        BlobETag = @BlobETag,
        IsDeleted = 0,
        LastIndexedUtc = sysutcdatetime()
    where BlobNameHash = @BlobNameHash
      and BlobName = @BlobName;

    if @@rowcount = 0
    begin
        insert into HR.EmployeeDocumentCatalog
        (
            BlobName,
            BlobNameHash,
            EmployeeId,
            DocumentTypeToken,
            DocumentTypeDisplay,
            UpdatedUtc,
            ContentType,
            BlobETag,
            IsDeleted,
            LastIndexedUtc
        )
        values
        (
            @BlobName,
            @BlobNameHash,
            @EmployeeId,
            @DocumentTypeToken,
            @DocumentTypeDisplay,
            @UpdatedUtc,
            @ContentType,
            @BlobETag,
            0,
            sysutcdatetime()
        );
    end
end
go