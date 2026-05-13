-- CII ✓
--  Employments Count 41
--  Terminations Count 20
--  Active Employments Count 21

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER VIEW [HR].[EmployeeDocumentsEmployees]
AS
SELECT
    E.PartyId EmployeeId
    ,P.NameLastFirst EmployeeName
    ,O.IoName HomeDepartment
    ,T.TerminationDate
FROM
    [dbo].[Employment] E
INNER JOIN
    [dbo].[Person] P
ON E.PartyId = P.PartyId
INNER JOIN
    [dbo].[InternalOrganization] O
ON E.HomeIoId = O.PartyId
LEFT OUTER JOIN
    [dbo].[Termination] T
ON E.TerminationId = T.TerminationId

GO
