-- CII database CiiSql ✓

/* ============================================================
   1) HR.EmployeeDocumentCatalog
   Optimize active-doc lookups and view projection
   ============================================================ */

-- A) Primary access path for active documents by employee + recency
--    (replaces broad IsDeleted/EmployeeId/UpdatedUtc index with a filtered one)
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_EmployeeDocumentCatalog_Active_Employee_UpdatedUtc'
      AND object_id = OBJECT_ID('HR.EmployeeDocumentCatalog')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_EmployeeDocumentCatalog_Active_Employee_UpdatedUtc]
    ON [HR].[EmployeeDocumentCatalog]
    (
        [EmployeeId] ASC,
        [UpdatedUtc] DESC,
        [Id] DESC
    )
    INCLUDE
    (
        [DocumentTypeDisplay],
        [ContentType],
        [BlobETag],
        [BlobName],
        [BlobNameHash]
    )
    WHERE [IsDeleted] = 0
    WITH (ONLINE = OFF, SORT_IN_TEMPDB = OFF);
END
GO

-- B) If you often fetch newest active docs globally (not just by employee),
--    this supports IsDeleted=0 + UpdatedUtc DESC queries.
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_EmployeeDocumentCatalog_Active_UpdatedUtc'
      AND object_id = OBJECT_ID('HR.EmployeeDocumentCatalog')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_EmployeeDocumentCatalog_Active_UpdatedUtc]
    ON [HR].[EmployeeDocumentCatalog]
    (
        [UpdatedUtc] DESC,
        [Id] DESC
    )
    INCLUDE
    (
        [EmployeeId],
        [DocumentTypeDisplay],
        [ContentType],
        [BlobETag],
        [BlobName],
        [BlobNameHash]
    )
    WHERE [IsDeleted] = 0
    WITH (ONLINE = OFF, SORT_IN_TEMPDB = OFF);
END
GO

-- C) Optional: if BlobNameHash is logically unique in your app, make it unique
--    to help cardinality and prevent dupes.
--    ONLY enable UNIQUE if data guarantees it.
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'UX_EmployeeDocumentCatalog_BlobNameHash'
      AND object_id = OBJECT_ID('HR.EmployeeDocumentCatalog')
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX [UX_EmployeeDocumentCatalog_BlobNameHash]
    ON [HR].[EmployeeDocumentCatalog]([BlobNameHash] ASC);
END
GO


/***************************************************************
  2) dbo.Employment
  Optimize join to Termination via TerminationId
 ***************************************************************/

-- Existing indexes are PartyId/Hired oriented; this one targets:
-- Employment.TerminationId -> Termination.TerminationId
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_Employment_TerminationId'
      AND object_id = OBJECT_ID('dbo.Employment')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_Employment_TerminationId]
    ON [dbo].[Employment]([TerminationId] ASC)
    INCLUDE ([PartyId], [HomeIoId])
    WHERE [TerminationId] IS NOT NULL
    WITH (ONLINE = OFF, SORT_IN_TEMPDB = OFF);
END
GO


/***************************************************************
  3) Optional cleanup (avoid overlapping/duplicate index cost)
 ***************************************************************/

-- After validating plans and usage, consider dropping/replacing these
-- if fully superseded to reduce write overhead:

DROP INDEX [IX_EmployeeDocumentCatalog_EmployeeId]
  ON [HR].[EmployeeDocumentCatalog];
GO

DROP INDEX [IX_EmployeeDocumentCatalog_IsDeleted_UpdatedUtc]
  ON [HR].[EmployeeDocumentCatalog];
GO

DROP INDEX [IX_EmployeeDocumentCatalog_SearchBase_v2]
  ON [HR].[EmployeeDocumentCatalog];
GO