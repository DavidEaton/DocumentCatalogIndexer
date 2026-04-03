create or alter procedure Common.usp_EmployeeDocumentCatalog_UpsertFromBlobEvent
    @BlobName            nvarchar(512),
    @BlobNameHash        varbinary(32),
    @EmployeeId          int,
    @DocumentTypeToken   nvarchar(200),
    @DocumentTypeDisplay nvarchar(200),
    @UpdatedUtc          datetimeoffset(7) = null,
    @BlobLastModifiedUtc datetimeoffset(7) = null,
    @ContentType         nvarchar(200) = null,
    @BlobETag            nvarchar(128) = null
as
begin
    set nocount on;
    set xact_abort on;

    update Common.EmployeeDocumentCatalog
    set
        EmployeeId = @EmployeeId,
        DocumentTypeToken = @DocumentTypeToken,
        DocumentTypeDisplay = @DocumentTypeDisplay,
        UpdatedUtc = @UpdatedUtc,
        BlobLastModifiedUtc = @BlobLastModifiedUtc,
        ContentType = @ContentType,
        BlobETag = @BlobETag,
        IsDeleted = 0,
        LastIndexedUtc = sysutcdatetime()
    where BlobNameHash = @BlobNameHash
      and BlobName = @BlobName;

    if @@rowcount = 0
    begin
        insert into Common.EmployeeDocumentCatalog
        (
            BlobName,
            BlobNameHash,
            EmployeeId,
            DocumentTypeToken,
            DocumentTypeDisplay,
            UpdatedUtc,
            BlobLastModifiedUtc,
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
            @BlobLastModifiedUtc,
            @ContentType,
            @BlobETag,
            0,
            sysutcdatetime()
        );
    end
end
go