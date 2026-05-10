-- Run in 
-- CII database CiiSql ✓
-- CSI database CsiSql 
-- DSI database DsiSql
-- DSN database DsnSql

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Replaces [Common].[EmployeeDocumentCatalog]
CREATE TABLE [HR].[EmployeeDocumentCatalog]
(
	[Id] [bigint] IDENTITY(1,1) NOT NULL,
	[BlobName] [nvarchar](512) NOT NULL,
	[BlobNameHash] [varbinary](32) NOT NULL,
	[EmployeeId] [int] NOT NULL,
	[DocumentTypeToken] [nvarchar](200) NOT NULL,
	[DocumentTypeDisplay] [nvarchar](200) NOT NULL,
	[UpdatedUtc] [datetimeoffset](7) NULL,
	[ContentType] [nvarchar](200) NULL,
	[BlobETag] [nvarchar](128) NULL,
	[IsDeleted] [bit] NOT NULL,
	[LastIndexedUtc] [datetimeoffset](7) NOT NULL
) ON [PRIMARY]
GO
ALTER TABLE [HR].[EmployeeDocumentCatalog] ADD  CONSTRAINT [PK_EmployeeDocumentCatalog] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_EmployeeDocumentCatalog_BlobHash] ON [HR].[EmployeeDocumentCatalog]
(
	[BlobNameHash] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_EmployeeDocumentCatalog_BlobName] ON [HR].[EmployeeDocumentCatalog]
(
	[BlobName] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IX_EmployeeDocumentCatalog_EmployeeId] ON [HR].[EmployeeDocumentCatalog]
(
	[EmployeeId] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IX_EmployeeDocumentCatalog_IsDeleted_UpdatedUtc] ON [HR].[EmployeeDocumentCatalog]
(
	[IsDeleted] ASC,
	[UpdatedUtc] DESC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IX_EmployeeDocumentCatalog_SearchBase_v2] ON [HR].[EmployeeDocumentCatalog]
(
	[IsDeleted] ASC,
	[EmployeeId] ASC,
	[UpdatedUtc] DESC
)
INCLUDE([BlobName],[DocumentTypeDisplay],[ContentType]) WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
ALTER TABLE [HR].[EmployeeDocumentCatalog] ADD  CONSTRAINT [DF_EmployeeDocumentCatalog_IsDeleted]  DEFAULT ((0)) FOR [IsDeleted]
GO
