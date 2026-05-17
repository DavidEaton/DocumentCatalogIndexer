SELECT *
FROM [HR].[EmployeeDocumentsCatalog]
WHERE [TerminationDate] IS NOT NULL
  AND TRY_CONVERT(date, [TerminationDate]) IS NULL;
GO