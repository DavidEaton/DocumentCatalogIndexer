-- CSI database CsiSql ✓
-- DSI database DsiSql ✓
-- DSN database DsnSql ✓

/* 
    Recommended index additions / replacements for query performance.
    Review in lower env first, then deploy with ONLINE = ON if your edition supports it.
*/

------------------------------------------------------------
-- 1) EmployeeDocumentCatalog: primary access path for
--    active docs by employee, usually sorted by UpdatedUtc
------------------------------------------------------------
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_EmployeeDocumentCatalog_SearchBase_v2'
      AND object_id = OBJECT_ID('HR.EmployeeDocumentCatalog')
)
BEGIN
    DROP INDEX IX_EmployeeDocumentCatalog_SearchBase_v2
        ON HR.EmployeeDocumentCatalog;
END
GO

IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_EmployeeDocumentCatalog_ActiveEmp_Updated'
      AND object_id = OBJECT_ID('HR.EmployeeDocumentCatalog')
)
BEGIN
    DROP INDEX IX_EmployeeDocumentCatalog_ActiveEmp_Updated
        ON HR.EmployeeDocumentCatalog;

    CREATE NONCLUSTERED INDEX IX_EmployeeDocumentCatalog_ActiveEmp_Updated
    ON HR.EmployeeDocumentCatalog
    (
        IsDeleted ASC,          -- constant predicate in view/query
        EmployeeId ASC,         -- join/filter
        UpdatedUtc DESC,        -- common order-by / recent-first access
        Id ASC                  -- stable tie-breaker, helps ordered scans
    )
    INCLUDE
    (
        DocumentTypeDisplay,
        ContentType,
        BlobETag,
        BlobName,
        BlobNameHash
    )
    WITH (ONLINE = OFF, SORT_IN_TEMPDB = ON);
END
GO

------------------------------------------------------------
-- 2) EmployeeDocumentCatalog: efficient "all active docs
--    by recency" scans (cross-employee feeds/batches)
------------------------------------------------------------
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_EmployeeDocumentCatalog_IsDeleted_UpdatedUtc'
      AND object_id = OBJECT_ID('HR.EmployeeDocumentCatalog')
)
BEGIN
    DROP INDEX IX_EmployeeDocumentCatalog_IsDeleted_UpdatedUtc
        ON HR.EmployeeDocumentCatalog;
END
GO

IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_EmployeeDocumentCatalog_Active_Updated'
      AND object_id = OBJECT_ID('HR.EmployeeDocumentCatalog')
)
BEGIN
    DROP INDEX IX_EmployeeDocumentCatalog_Active_Updated
        ON HR.EmployeeDocumentCatalog;

    CREATE NONCLUSTERED INDEX IX_EmployeeDocumentCatalog_Active_Updated
    ON HR.EmployeeDocumentCatalog
    (
        IsDeleted ASC,
        UpdatedUtc DESC,
        Id ASC
    )
    INCLUDE
    (
        EmployeeId,
        DocumentTypeDisplay,
        ContentType,
        BlobETag,
        BlobName,
        BlobNameHash
    )
    WITH (ONLINE = OFF, SORT_IN_TEMPDB = ON);
END
GO

------------------------------------------------------------
-- 3) EmployeeDocumentCatalog: point lookup by BlobNameHash
--    (often exact match); make unique if business rules allow
------------------------------------------------------------
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_EmployeeDocumentCatalog_BlobHash'
      AND object_id = OBJECT_ID('HR.EmployeeDocumentCatalog')
)
BEGIN
    DROP INDEX IX_EmployeeDocumentCatalog_BlobHash
        ON HR.EmployeeDocumentCatalog;
END
GO

CREATE NONCLUSTERED INDEX IX_EmployeeDocumentCatalog_BlobHash
ON HR.EmployeeDocumentCatalog
(
    BlobNameHash ASC
)
INCLUDE
(
    Id,
    EmployeeId,
    IsDeleted,
    UpdatedUtc,
    BlobName,
    BlobETag,
    ContentType,
    DocumentTypeDisplay
)
WITH (ONLINE = OFF, SORT_IN_TEMPDB = ON);
GO

------------------------------------------------------------
-- 4) PartyRelationship: supports CTE in EmployeeDocumentsEmployees
--    WHERE PartyRoleTypeID = 3 AND PartyIDTo = constant
--    GROUP BY PartyIDFrom, MAX(ValidThru)
------------------------------------------------------------
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_PartyRelationship_Role_To_From_ValidThru'
      AND object_id = OBJECT_ID('HR.EmployeeDocumentCatalog')
)
BEGIN
    DROP INDEX IX_PartyRelationship_Role_To_From_ValidThru
        ON HR.EmployeeDocumentCatalog;
END
GO

CREATE NONCLUSTERED INDEX IX_PartyRelationship_Role_To_From_ValidThru
ON dbo.PartyRelationship
(
    PartyRoleTypeID ASC,
    PartyIDTo ASC,
    PartyIDFrom ASC,
    ValidThru DESC
)
WITH (ONLINE = OFF, SORT_IN_TEMPDB = ON);
GO

------------------------------------------------------------
-- 5) Optional: if BlobName lookups are exact-match and frequent,
--    keep existing index; if not used, consider removing after
--    monitoring usage (do not drop blindly in this script).
------------------------------------------------------------

/*
Post-deployment validation (recommended):
1) Capture actual execution plans for:
   - SELECTs against HR.EmployeeDocumentsCatalog
   - Employee-specific recent documents queries
   - BlobNameHash lookups
2) Compare logical reads / CPU before vs after.
3) Check write overhead (INSERT/UPDATE/DELETE) on EmployeeDocumentCatalog.
*/