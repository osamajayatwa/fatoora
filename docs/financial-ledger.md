# Financial Ledger architecture

`companies/{companyId}/financial_ledger_entries/{entryId}` is the authoritative
accounting source for Financial Ledger reports. It is a trusted, read-only
projection built atomically by posting transactions from confirmed invoices,
receipts, expenses, returns, settlements, and opening-balance records. Clients
cannot write it and reporting code must not reconstruct or alter its debit and
credit mappings. Confirmed invoice and sales-return `items[]` snapshots are the
authoritative source only for product-level export detail.

## Accounting mapping

| Source | Component | Debit | Credit |
| --- | --- | --- | --- |
| Invoice | paid-at-sale portion | actual company/rep cash | sales |
| Invoice | receivable portion | customer | sales |
| Receipt | allocated collection | actual cash or payment clearing | customer |
| Expense | company/rep cash | expenses | actual cash account |
| Expense | rep personal cash | expenses | representative payable |
| Sales return | sale reversal | sales | customer |
| Sales return | cash refund | customer | verified collection cash account |
| Settlement | rep-to-company transfer | company cash | representative cash |
| Customer opening balance | customer owes | customer | opening-balance equity |
| Customer opening balance | customer credit | opening-balance equity | customer |
| Company cash opening | opening cash | company cash | opening-balance equity |

One economic event may generate more than one component. This is intentional:
partial invoices separate cash and receivable portions, cash-refunded returns
separate the sale reversal from the cash refund, and receipts allocated across
representatives are split by authoritative invoice ownership. Source-side cash
and customer transaction rows are not independently projected when that would
double count the same event.

## Representative ownership

Ledger filtering always uses `salesRepId`; `salesRepName` is a display snapshot.
Invoice and return ownership comes from the invoice's `salesRepId`. Settlement
and representative expense ownership comes from their own `salesRepId`.
Receipt ownership is grouped from allocated invoices. An unallocated admin
receipt or admin-posted customer opening balance remains unassigned rather than
being inferred from `createdByUid` or the customer's creator.

## Query model and summaries

Schema v3 keeps search out of the main key Cartesian product. Every main row
contains at most 24 fixed-width SHA-256 `queryKeys`, covering only canonical
combinations of movement type, either posted account, customer, and payment
method. The page query applies one `array-contains` key plus the date range. A
representative selection also applies `salesRepId == uid`. Results order by
`occurredAt` and document ID, and use a value cursor for stable pagination.

Search uses the backend-only
`financial_ledger_search_entries/{ledgerEntryId}` projection. It contains at
most 96 fixed-width SHA-256 tokens for the reference number, customer name,
description, and notes. A trusted callable applies the search token, date, and
optional representative constraints in Firestore, then checks the compact base
filter key within a bounded candidate page. It never downloads the full ledger
to Flutter.

Summary values are materialized into backend-only daily documents for every
compact query key and for both company and authoritative representative scope.
Each entry deterministically selects one of 16 summary shards. The projection
trigger reconciles search, summary, and per-entry state in one idempotent
transaction.

The local manifest contains four main ledger composites (ascending/descending,
with/without representative) and two descending search composites
(with/without representative). No metric field participates in a composite
index. The array fields retain explicit single-field exemptions.

## Account-activity and opening-balance projection

The backend-only account reporting projection is derived exclusively from
`financial_ledger_entries`. A trusted `onDocumentWritten` trigger reconciles
the previous and current ledger row in one Firestore transaction. It writes no
business/source document and never changes trusted posting mappings.

Projection version 1 uses these collections:

```text
companies/{companyId}/financial_ledger_account_activity_states/{entryId}
companies/{companyId}/financial_ledger_account_activity_metadata/current
companies/{companyId}/financial_ledger_account_activity_scopes/{scope}/
  accounts/{sha256(accountKey)}/months/{YYYY-MM}_{shard}
  accounts/{sha256(accountKey)}/days/{YYYY-MM-DD}_{shard}
  accounts/{sha256(accountKey)}/postings/{day}_{timestamp}_{entryHash}
```

`scope` is `all` or a SHA-256 representative scope. Aggregate documents store
the stable account key/type/name, entry count, debit total, credit total, and
net change. Posting documents store the same account identity, ledger entry
ID, exact occurrence time, debit, credit, and net change. State documents store
the source fingerprint and allow idempotent update/delete reconciliation. The
metadata document is written only after a guarded apply finishes and marks the
projection ready; the opening callable fails closed while it is missing.

The admin-only `getFinancialLedgerOpeningBalances` callable accepts a company,
account keys, optional `salesRepId`, and `fromInclusive`. It sums completed
months, completed days in the current month, and exact current-day postings
whose timestamps are strictly before `fromInclusive`. Thus a report never
assumes a zero balance at the selected start date. Clients have no direct read
or write access to any account-activity projection collection.

No new composite Firestore index is required: all opening queries target a
fixed account subcollection and use document-ID ranges. Existing Financial
Ledger query/search composite indexes remain required.

## Professional accounting workbook

The admin action `تصدير التقرير المحاسبي / Export Accounting Report` downloads
the complete matching dataset, not only the loaded page. The generated XLSX
contains exactly these sheets:

1. `الملخص Summary`: company, period, Asia/Amman timezone, active filters,
   representative, row/posting counts, debit/credit totals, difference,
   balanced validation, and legacy-data warnings.
2. `القيود Journal`: one row per authoritative ledger entry, with the same
   positive amount in explicit debit and credit columns.
3. `تفاصيل المبيعات`: product rows from confirmed invoice and return immutable
   `items[]` snapshots. Source IDs are deduplicated so partial invoice posting
   components and return/refund components cannot duplicate product lines.
4. `الأستاذ العام GL`: one debit posting and one credit posting per Journal
   row, grouped by account, with a brought-forward balance, running balance,
   and debit/credit balance side.

The workbook builder does not read `items/{itemId}`. Missing or incomplete
legacy snapshots are reported as warnings instead of being silently repaired
from mutable catalog data. Account names and source metadata are display
snapshots; amounts and account sides always come from the ledger.

On Web, saving starts a normal browser download. On Android, saving opens the
system document picker so the administrator can select Downloads or another
visible folder. Canceling the picker is treated as a failed save and never
produces a success notification.

## Maintenance and rollout

The account-activity maintenance command reads only
`financial_ledger_entries` and builds only the new state/scope collections.
Dry-run is the default:

```powershell
npm --prefix functions run rebuild:financial-ledger-account-activity -- `
  --project=<project-id> `
  --company=<company-id>
```

Apply mode requires explicit intent, exact project/company confirmation, and a
conservative maximum-write ceiling:

```powershell
npm --prefix functions run rebuild:financial-ledger-account-activity -- `
  --project=<project-id> `
  --company=<company-id> `
  --apply `
  --confirm-project=<project-id> `
  --confirm-company=<company-id> `
  --max-writes=5000
```

Review dry-run output before any apply. Deploy the account projection trigger,
opening-balance callable, and Firestore rules before enabling the export; run
the dry-run; then run a separately approved apply. No index deployment is
needed for the new projection.
