DROP TABLE IF EXISTS Common.EmployeeDocumentCatalog;

BEGIN
    create table Common.EmployeeDocumentCatalog
(
    Id                    bigint identity(1,1) not null
        constraint PK_EmployeeDocumentCatalog primary key clustered,
    BlobName              nvarchar(512) not null,
    BlobNameHash          varbinary(32) not null,
    EmployeeId            int not null,
    DocumentTypeToken     nvarchar(200) not null,
    DocumentTypeDisplay   nvarchar(200) not null,
    UpdatedUtc            datetimeoffset(7) null,
    BlobLastModifiedUtc   datetimeoffset(7) null,
    ContentType           nvarchar(200) null,
    BlobETag              nvarchar(128) null,
    IsDeleted             bit not null
        constraint DF_EmployeeDocumentCatalog_IsDeleted default (0),
    LastIndexedUtc        datetimeoffset(7) not null
);

create index IX_EmployeeDocumentCatalog_BlobHash
    on Common.EmployeeDocumentCatalog (BlobNameHash);

create index IX_EmployeeDocumentCatalog_BlobName
    on Common.EmployeeDocumentCatalog (BlobName);

create index IX_EmployeeDocumentCatalog_EmployeeId
    on Common.EmployeeDocumentCatalog (EmployeeId);

create index IX_EmployeeDocumentCatalog_IsDeleted_UpdatedUtc
    on Common.EmployeeDocumentCatalog (IsDeleted, UpdatedUtc desc);

END