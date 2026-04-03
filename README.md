# Document Catalog Indexer (Azure Function)

## Overview

`Document Catalog Indexer` is an **event-driven Azure Function** responsible for maintaining the **Employee Document Catalog** in each company database.

Instead of performing expensive, batch-style indexing inside the Employee Documents Viewer web application, this service:

* Reacts to **Blob Storage events** (create/update/delete)
* Processes **one blob at a time**
* Updates the catalog via **stored procedures**
* Uses **Managed Identity** for secure, secretless access to Azure SQL and Blob Storage

This design eliminates:

* Startup indexing delays
* Full container scans
* Large SQL batch upserts
* Embedded credentials or secrets in configuration

---

## Architecture

```
Blob Storage (hrdocs container)
        │
        ▼
Event Grid
        │
        ▼
Azure Function (DocumentCatalogIndexer)
        │
        ├── Blob Metadata (Managed Identity)
        └── SQL Stored Procedures (Managed Identity)
                │
                ▼
EmployeeDocumentCatalog (per-company database)
```

### Key Properties

* **Event-driven** (no polling, no cron jobs)
* **Per-blob updates** (O(1) work per event)
* **Stateless function execution**
* **Database owns mutation logic**
* **Web app is read-only (query + stream)**

---

## Supported Storage Containers

| Company | Storage Account | Container |
| ------- | --------------- | --------- |
| CII     | `cii`           | `hrdocs`  |
| CSI     | `csii`          | `hrdocs`  |
| DSI     | `dsii`          | `hrdocs`  |
| DSN     | `dsni`          | `hrdocs`  |

---

## Event Handling

### Supported Events

* `Blob Created`
* `Blob Deleted`
* `Blob Renamed`
* `Directory Created`
* `Directory Deleted`
* `Directory Renamed`

### Behavior

| Event Type  | Action                                     |
| ----------- | ------------------------------------------ |
| BlobCreated | Parse → Read metadata → Upsert catalog row |
| BlobDeleted | Mark catalog row as deleted                |
...
---

## Blob Naming Convention

Blobs must follow:

```
<EmployeeId>_<DocumentType>.pdf
```

Examples:

```
12345_W2.pdf
67890_PayStub.pdf
```

### Parsing Rules

* `EmployeeId` → integer prefix
* `DocumentTypeToken` → remaining name
* `DocumentTypeDisplay` → humanized version

Invalid blobs are ignored.

---

## Security Model (Managed Identity)

### No secrets are stored.

The Function App uses **System Assigned Managed Identity** to access:

* Azure SQL
* Azure Blob Storage

---

## Required Azure Configuration

### 1. Enable Managed Identity

Function App → **Identity**

* Enable **System Assigned**

---

### 2. Grant Blob Access

For each storage account:

**IAM → Add Role Assignment**

* Role: `Storage Blob Data Reader`
* Assign to: Function App managed identity

---

### 3. Grant SQL Access

In each company database:

```sql
CREATE USER [DocumentCatalogIndexer] FROM EXTERNAL PROVIDER;
GO

GRANT EXECUTE ON OBJECT::Common.usp_EmployeeDocumentCatalog_UpsertFromBlobEvent TO [DocumentCatalogIndexer];
GRANT EXECUTE ON OBJECT::Common.usp_EmployeeDocumentCatalog_MarkDeletedByBlobName TO [DocumentCatalogIndexer];
GRANT EXECUTE ON OBJECT::Common.usp_EmployeeDocumentCatalog_Search TO [DocumentCatalogIndexer];
GO
```

---

### 4. Configure Event Grid

For each storage account:

* Navigate to **Events**
* Create **Event Subscription**

#### Settings

* Event Types:

  * Blob Created
  * Blob Deleted
  * Blob Renamed
  * Directory Created
  * Directory Deleted
  * Directory Renamed
* Endpoint Type: Azure Function
* Function: `BlobCatalogEventFunction`

#### Filters

```
Subject begins with:
/blobServices/default/containers/hrdocs/
```

---

## Required App Settings (Non-Secret)

| Setting                | Example                              |
| ---------------------- | ------------------------------------ |
| `CII_SQL_SERVER`       | `e04vmu8qq9.database.windows.net`    |
| `CII_SQL_DATABASE`     | `CiiSql`                             |
| `CII_BLOB_ACCOUNT_URL` | `https://cii.blob.core.windows.net/` |

Repeat for:

* CSI
* DSI
* DSN

---

## Database Objects

Each company database must contain:

### Table

* `Common.EmployeeDocumentCatalog`

### Stored Procedures

* `usp_EmployeeDocumentCatalog_UpsertFromBlobEvent`
* `usp_EmployeeDocumentCatalog_MarkDeletedByBlobName`
* `usp_EmployeeDocumentCatalog_Search`

### View

* `vw_EmployeeDocumentCatalogSearchBase`

---

## Local Development

### Prerequisites

* .NET SDK
* Azure Functions Core Tools
* Azure CLI logged in

---

### Run locally

```bash
func start
```

### Local settings

Use `local.settings.json`:

```json
{
  "Values": {
    "CII_SQL_SERVER": "...",
    "CII_SQL_DATABASE": "...",
    "CII_BLOB_ACCOUNT_URL": "https://cii.blob.core.windows.net/"
  }
}
```

---

## Deployment

```bash
func azure functionapp publish DocumentCatalogIndexer
```

---

## Testing

### Trigger manually

1. Upload blob → verify:

   * Function logs
   * SQL row inserted

2. Delete blob → verify:

   * Row marked `IsDeleted = 1`

---

## Observability

* Application Insights enabled
* Logs include:

  * Event type
  * Company
  * Blob name
  * Processing outcome

---

## Failure Handling

* Functions are **idempotent**
* Duplicate events are safe
* Failures:

  * Logged to Application Insights
  * Can be retried automatically by Event Grid

---

## Initial Backfill (Required Once)

Event-driven indexing does **not** process existing blobs.

Run a one-time backfill:

* Temporary console tool
* OR admin-triggered function

After that, Event Grid maintains consistency.

---

## Design Principles

### Premises

* Blobs are mostly immutable
* Indexing is rare compared to reads
* Startup latency must be minimal

### Conclusions

* Index only when changes occur
* Push mutation logic into SQL
* Keep web app read-only
* Eliminate batch reconciliation

---

## Summary

This system replaces:

*  Batch indexing
*  Startup delays
*  Blob scans
*  Embedded secrets

With:

* Event-driven updates
* Per-blob processing
* Managed identity security
* SQL-owned logic
* Fast, scalable architecture

---

## Ownership

This **Document Catalog Indexer** Azure Function App is the **single source of truth for catalog mutation**.

The **Employee Documents Viewer** web application **never attempts to rebuild or reconcile the catalog**.
