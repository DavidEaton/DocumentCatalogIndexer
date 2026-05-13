-- CII ✓
-- CSI ✓
-- DSI ✓
-- DSN ✓

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER VIEW [HR].[EmployeeDocumentsCatalog]
AS
    SELECT
        E.EmployeeId
        , E.EmployeeName
        , E.HomeDepartment
        , E.TerminationDate
        , C.DocumentTypeDisplay
        , YEAR(C.UpdatedUtc) AS [Year]
    FROM [HR].[EmployeeDocumentCatalog] C
        INNER JOIN
        [HR].[EmployeeDocumentsEmployees] E
        ON E.EmployeeId = C.EmployeeId
    WHERE C.IsDeleted = 0;      
GO
