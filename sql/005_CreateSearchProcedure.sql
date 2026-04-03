create or alter procedure Common.usp_EmployeeDocumentCatalog_Search
    @SearchTerm      nvarchar(200) = null,
    @SortColumn      sysname,
    @SortDescending  bit,
    @Start           int,
    @Length          int
as
begin
    set nocount on;

    create table #Filtered
    (
        BlobName         nvarchar(512)      not null,
        EmployeeId       int                not null,
        Employee         nvarchar(256)      not null,
        Department       nvarchar(256)      null,
        DocumentType     nvarchar(200)      not null,
        [Year]           int                null,
        UpdatedUtc       datetimeoffset(7)  null,
        ContentType      nvarchar(200)      null,
        Active           bit                not null,
        TerminationDate  datetime           null
    );

    insert into #Filtered
    (
        BlobName,
        EmployeeId,
        Employee,
        Department,
        DocumentType,
        [Year],
        UpdatedUtc,
        ContentType,
        Active,
        TerminationDate
    )
    select
        BlobName,
        EmployeeId,
        Employee,
        Department,
        DocumentType,
        [Year],
        UpdatedUtc,
        ContentType,
        Active,
        TerminationDate
    from Common.vw_EmployeeDocumentCatalogSearchBase
    where
        @SearchTerm is null
        or @SearchTerm = N''
        or Employee like N'%' + @SearchTerm + N'%'
        or Department like N'%' + @SearchTerm + N'%'
        or DocumentType like N'%' + @SearchTerm + N'%'
        or BlobName like N'%' + @SearchTerm + N'%'
        or cast(EmployeeId as nvarchar(20)) like N'%' + @SearchTerm + N'%'
        or cast([Year] as nvarchar(10)) like N'%' + @SearchTerm + N'%'
        or case when Active = 1 then N'Active' else N'Terminated' end like N'%' + @SearchTerm + N'%'
        or convert(nvarchar(10), TerminationDate, 23) like N'%' + @SearchTerm + N'%';

    select count(*) as TotalCount
    from Common.vw_EmployeeDocumentCatalogSearchBase;

    select count(*) as FilteredCount
    from #Filtered;

    if @SortColumn = N'EmployeeId' and @SortDescending = 0
        select * from #Filtered order by EmployeeId asc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'EmployeeId' and @SortDescending = 1
        select * from #Filtered order by EmployeeId desc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'Employee' and @SortDescending = 0
        select * from #Filtered order by Employee asc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'Employee' and @SortDescending = 1
        select * from #Filtered order by Employee desc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'Department' and @SortDescending = 0
        select * from #Filtered order by Department asc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'Department' and @SortDescending = 1
        select * from #Filtered order by Department desc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'DocumentType' and @SortDescending = 0
        select * from #Filtered order by DocumentType asc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'DocumentType' and @SortDescending = 1
        select * from #Filtered order by DocumentType desc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'Year' and @SortDescending = 0
        select * from #Filtered order by [Year] asc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'Year' and @SortDescending = 1
        select * from #Filtered order by [Year] desc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'Active' and @SortDescending = 0
        select * from #Filtered order by Active asc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'Active' and @SortDescending = 1
        select * from #Filtered order by Active desc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'TerminationDate' and @SortDescending = 0
        select * from #Filtered order by TerminationDate asc offset @Start rows fetch next @Length rows only;
    else if @SortColumn = N'TerminationDate' and @SortDescending = 1
        select * from #Filtered order by TerminationDate desc offset @Start rows fetch next @Length rows only;
    else
        select * from #Filtered order by UpdatedUtc desc, Employee asc offset @Start rows fetch next @Length rows only;
end
go