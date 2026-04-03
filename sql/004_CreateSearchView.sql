create or alter view Common.vw_EmployeeDocumentCatalogSearchBase
as
select
    d.BlobName,
    d.EmployeeId,
    emp.NameLastFirst as Employee,
    emp.HomeDepartment as Department,
    d.DocumentTypeDisplay as DocumentType,
    year(coalesce(d.UpdatedUtc, d.BlobLastModifiedUtc)) as [Year],
    coalesce(d.UpdatedUtc, d.BlobLastModifiedUtc) as UpdatedUtc,
    d.ContentType,
    emp.Active,
    term.TerminationDate
from Common.EmployeeDocumentCatalog d
inner join Common.EmployeeEeDocsLookup emp
    on emp.Id = d.EmployeeId
outer apply
(
    select top (1)
        tm.TerminationDate
    from HR.Terminations tm
    where tm.PartyID = emp.Id
    order by tm.TerminationDate desc
) term
where d.IsDeleted = 0;
go