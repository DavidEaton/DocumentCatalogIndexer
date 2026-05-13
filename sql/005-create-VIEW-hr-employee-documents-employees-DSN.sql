-- DSN ✓
--  Employments Count 5518
--  Terminations Count 5304
--  Active Employments Count 234

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER VIEW [HR].[EmployeeDocumentsEmployees]
AS
WITH EmployeeRelationship AS
(
    SELECT
        R.PartyIDFrom EmployeeId,
        MAX(R.ValidThru) TerminationDate
    FROM [dbo].[PartyRelationship] R
    WHERE R.PartyRoleTypeID = 3
      AND R.PartyIDTo = 1
    GROUP BY
        R.PartyIDFrom
)
SELECT
    ER.EmployeeId
    ,P.NameLastFirst EmployeeName
    ,D.DepartmentName HomeDepartment
    ,ER.TerminationDate
FROM EmployeeRelationship ER
INNER JOIN [dbo].[Person] P
    ON P.PartyID = ER.EmployeeId
OUTER APPLY
(
    SELECT TOP (1)
        H.DepartmentID
    FROM [dbo].[HomeDepartment] H
    WHERE H.PartyID = P.PartyID
    ORDER BY H.Created DESC
) H
LEFT OUTER JOIN [dbo].[Department] D
    ON D.PartyID = H.DepartmentID;