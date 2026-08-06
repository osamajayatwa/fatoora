# Production maintenance commands

These commands use the Firebase Admin SDK and therefore bypass Firestore
security rules. Run them only with an explicitly selected project and company.
Production access requires Application Default Credentials, for example:

```powershell
gcloud auth application-default login
```

## Reconcile materialized cash balances

Cash reconciliation is read-only by default. It scans every `cash_movements`
page, reports every company and representative account, and writes nothing:

```powershell
npm --prefix functions run reconcile:cash -- `
  --project=fatoora-6b192 `
  --company=default_company
```

The report includes movement count, total IN, total OUT, calculated balance,
stored balance, and difference for each account. Malformed identities or
amounts, duplicate posting identities, missing representative IDs, ambiguous
sources/accounts, and unsupported movement types prevent apply mode.

Apply mode must be run only after reviewing a clean dry-run and deploying the
trusted Functions version that honors the cash-reconciliation maintenance
lock. It requires exact project and company confirmation:

```powershell
npm --prefix functions run reconcile:cash -- `
  --project=fatoora-6b192 `
  --company=default_company `
  --apply `
  --confirm-project=fatoora-6b192 `
  --confirm-company=default_company `
  --max-writes=400
```

The command never edits `cash_movements`. Balance writes and lock release are
committed atomically and are idempotent. If a process interruption leaves an
active lock, inspect the recorded run ID and resume the same frozen scan with
`--resume-run=<run-id>`; do not clear the lock manually while the outcome is
unknown.

## Audit legacy invoice ownership

The audit is read-only. It reports missing, null/empty, and potentially
conflicting `salesRepId` values, including counts by invoice type and status.

```powershell
npm --prefix functions run audit:invoice-sales-rep -- `
  --project=fatoora-6b192 `
  --company=default_company
```

Quotation conversions are checked through `convertedInvoiceId`. A difference
between `salesRepId` and `createdByUid` is reported for review when no converted
quotation explains it; it is not automatically treated as corrupt data.

## Plan or apply a backfill

Dry-run is the default and performs no writes:

```powershell
npm --prefix functions run backfill:invoice-sales-rep -- `
  --project=fatoora-6b192 `
  --company=default_company
```

The backfill proposes only a `salesRepId` update. It does not recalculate or
change totals, payments, document numbers, dates, status, or financial posting
fields. Ownership is accepted only when:

1. exactly one converted quotation identifies a valid admin/sales-rep user; or
2. `createdByUid` identifies a valid admin/sales-rep user.

Ambiguous quotation ownership, deleted/unknown users, unsupported roles, and a
sales-rep name without a UID are skipped. Customer ownership is intentionally
not used because it is not reliable evidence of invoice assignment.

After reviewing the dry-run, apply mode requires exact project and company
confirmation. It also uses Firestore update-time preconditions and refuses more
than 500 writes unless `--max-writes` is deliberately increased:

```powershell
npm --prefix functions run backfill:invoice-sales-rep -- `
  --project=fatoora-6b192 `
  --company=default_company `
  --apply `
  --confirm-project=fatoora-6b192 `
  --confirm-company=default_company `
  --max-writes=500
```

Run the audit again immediately after any applied backfill.

## Stock movement ownership limitation

Stock movements currently contain `createdByUid` but not `salesRepId`, so rules
scope sales-rep reads using `createdByUid`. This is acceptable for the current
release because inventory/stock-movement screens are admin routes and the rule
still prevents one rep from reading another rep's movements.

The limitation is that a movement posted by an admin for a rep-assigned invoice
is admin-owned and is not visible to that rep. If rep-facing stock history is
added later, new stock movements should persist immutable `salesRepId` and
rules/queries should migrate to that field. No schema change is required now.

## Firestore deployment and verification

Use an account with permission to read/deploy Firestore rules and indexes:

```powershell
firebase login
firebase use fatoora-6b192
firebase firestore:indexes --project fatoora-6b192
firebase deploy --only firestore:rules --project fatoora-6b192
firebase deploy --only firestore:indexes --project fatoora-6b192
firebase firestore:indexes --project fatoora-6b192
```

Before approving any index deletion prompt, compare live indexes with
`firestore.indexes.json` and merge any live-only definitions. After deployment:

- confirm the intended ruleset is the active ruleset;
- confirm every declared index reaches `READY`;
- confirm no unrelated index was deleted;
- test that Rep A cannot directly read or query Rep B documents;
- test that Rep B cannot directly read or query Rep A documents;
- test that admin can still directly read and list all protected collections.
