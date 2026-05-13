-- CSI ✓
--  Employments Count 457
--  Terminations Count 402
--  Active Employments Count 58

-- DSI ✓
--  Employments Count 1548
--  Terminations Count 1446
--  Active Employments Count 108

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER VIEW [HR].[EmployeeDocumentsEmployees]
AS
WITH EmployeeCompanyRelationship AS
(
    SELECT
        PR.PartyIDFrom AS PartyID,
        MAX(PR.ValidThru) TerminationDate
    FROM [dbo].[PartyRelationship] PR
    WHERE PR.PartyRoleTypeID = 3
      AND PR.PartyIDTo = 1055707269
    GROUP BY
        PR.PartyIDFrom
)
SELECT
    P.PartyID EmployeeId,
    P.NameLastFirst EmployeeName,
    D.DepartmentName HomeDepartment,
    ECR.TerminationDate
FROM [dbo].[Person] P
INNER JOIN EmployeeCompanyRelationship ECR
    ON ECR.PartyID = P.PartyID
LEFT OUTER JOIN [dbo].[HomeDepartment] H
    ON P.PartyID = H.PartyID
LEFT OUTER JOIN [dbo].[Department] D
    ON H.DepartmentID = D.PartyID;
GO