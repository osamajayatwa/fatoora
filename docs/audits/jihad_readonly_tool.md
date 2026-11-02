# Jihad bounded read-only audit tool

This tool prepares the previously approved investigation for execution from the
user's normal terminal. **Production has not been audited by this tool yet.** The
user's successful HTTP 200 diagnostic established a working authenticated API
request with zero returned records; it did not establish Jihad's identity or
reconcile any invoice. The earlier agent connection was network-restricted.

This adds focused investigation support to
[the existing audit](inventory_financial_integrity_audit.md), without repeating
its full synthetic audit or making a deployment claim.

## Run from PowerShell

Use the same normal, non-elevated terminal and existing user Application Default
Credentials that passed `diagnose_readonly_production_access.js`:

```powershell
Set-Location C:\src\fatoora\functions
node .\scripts\audit_jihad_readonly.js --project=fatoora-6b192
$LASTEXITCODE
```

Node 22 and the existing installed repository dependencies are required. No new
login, credentials file, browser session, Firebase CLI token, or service account
is required or extracted. The tool reuses the diagnostic's installed GoogleAuth
SDK `UserRefreshClient` and authenticated Firestore REST requests. These use
existing Google IAM authorization; this does not exercise Firebase client
security rules. Permission errors stop the run without a fallback identity or
rules change. There is no browser access or URL-verification workaround.

Production execution rejects emulator and explicit credential-file environment
overrides, debugging contexts that could log requests, and mutation flags such
as `--apply`. Use a normal terminal without those overrides. If authentication
or permissions fail, retain the safe blocker code and stop; any new access or
scope needs separate approval. A query/index or snapshot-time rejection also
stops the run; this tool never creates an index or changes configuration.

Reports default to a new directory under:

```text
%LOCALAPPDATA%\Fatoora\PrivateAudits\<UTC timestamp>-<random>\
  findings.private.json
  summary.shareable.json
```

The directory is printed after the run. An optional absolute `--output-dir=...`
must resolve outside this workspace and every Git repository; junctions are
resolved and existing report files are never overwritten. Default storage uses
the local user's AppData permissions. Keep it in private, unsynchronized local
storage. Only share `summary.shareable.json`. Do not paste the private report
into Git, issue trackers, shared logs, or chat. It contains operational IDs and
financial comparisons needed for local review, though no customer names,
contacts, free text, account keys containing customer IDs, credentials, or raw
document exports are included.

## Scope and actual schema

The reader exposes only Firestore `runQuery`, `runAggregationQuery`, and
`batchGet`. It never imports a production Admin database write handle. POST is
the transport for these read RPCs. Synthetic fixture writes exist only in the
test harness, in the isolated loopback `demo-jihad-readonly` project.

| Source | Scope / established relationship |
|---|---|
| Root `users` | Bounded stored-name prefix queries for Jihad/Jehad and Arabic جهاد variants; unique `sales_rep` UID and actual company required |
| Company `invoices` | `salesRepId`, `createdByUid`, or `stockSourceSalesRepId` equals that UID; exact invoice references from own movements |
| `rep_inventory_balances`, `rep_inventory_movements` | Only that UID; balance identity is `${salesRepId}_${itemId}` |
| `inventory_transfers` | That UID or exact own-movement `inventoryTransfer` reference |
| `sales_returns` | `originalInvoiceId` in inspected invoices, explicit invoice return IDs, or own-movement `salesReturn` reference |
| `stock_movements` | Only reference IDs of the inspected invoices, transfers, and returns; recorded reference types verified |
| Root `items` | Only item IDs in that representative's custody or invoice lines; projected fields and explicit company ownership checked |
| `audit_events` | Only actual `entityType` / `entityId` pairs for those sources and items; item tracking changes stripped to booleans |
| `receipts` | Exact active/cancelled receipt IDs linked by inspected invoices; allocations outside the cohort stop the run |
| `customers` | Only customers of posted inspected invoices; numeric projections only, aliases in reports |
| `customer_transactions`, `cash_movements`, `financial_ledger_entries` | Source collection/ID pairs and declared posting IDs for those sources; scoped customer opening transactions and their journals |

All company collections are under `companies/<actual companyId>/...`. These
relationships come from the repository's trusted posting code and existing
reconciliation utility. Source ownership mismatches are rejected or reported;
no unrelated representative's transaction history is fetched. Root identity
queries retrieve only minimal profile fields, with a total 20-profile ceiling.
Zero or multiple matching representatives stops the run; it does not guess from
display names or expand to a full user scan. Unrecognized spelling requires
human identity review before changing the lookup.

Queries count first, project fields, and paginate 25 documents at a time. An
initial server read timestamp pins every subsequent read and count, preventing
concurrent balance/projection updates from mixing snapshots. Missing or
inconsistent read timestamps stop the run. Confirmed invoices are analyzed
first. If the relevant cohort exceeds 200, the tool stops before fetching invoice
documents rather than certifying a truncated custody history.

| Hard ceiling | Limit |
|---|---:|
| Unique invoices, including linked invoices | 200 |
| Profiles / custody balances / referenced items | 20 / 500 / 500 |
| Own custody movements / warehouse counterpart movements | 1,000 / 1,000 |
| Transfers / returns / audit events | 200 / 400 / 1,000 |
| Receipts / customers | 400 / 200 |
| Customer transactions / cash movements / journals | 1,200 / 1,000 / 1,200 |
| All returned or missing documents combined | 5,000 |
| Read RPCs / audit elapsed time | 500 / 10 minutes |

Authentication discovery has an 8-second guard; individual API requests have a
20-second timeout and no resource-request retries. Budget failure stops further
reads. Counts and returned-document totals are reported separately from unique
scoped records; counts can inspect index entries without returning documents.

## Reconstruction and evidence limits

The audit reuses exact thousandth conversion from
`integrity_reconciliation.js`. Arithmetic uses BigInt, fixed three-decimal output,
and independent half-away-from-zero invoice/return allocation. Invalid precision,
malformed numeric state, unsupported source types, or ambiguous links block a
trusted conclusion. Posting calculators are not used as the reconciliation
oracle.

Expected custody is reconstructed from confirmed deliveries, original sale
lines and stock source, confirmed returns, and custody-to-warehouse transfers.
It is compared separately with actual IN/OUT movements and persisted balances.
Each movement equation and zero-opening chronological custody chain is checked.
The first recorded nonzero `quantityBefore` is never accepted as an opening.
Missing opening/source history blocks reconciliation. Physical delivery still
requires independent business evidence before any correction.

Historical tracking is established by an immutable line snapshot or recorded
source OUT evidence. A current item flag, local fix, or incomplete item audit
trail cannot prove posting-time state. Unknown tracking yields conditional sale
quantities in the private report and BLOCKED, with no invented missing-deduction
conclusion. Positive custody with tracking currently disabled is reported as a
current risk. No deployed code version is assumed or inferred from test success;
`localFixDeployment` remains `NOT_QUERIED_OR_ASSUMED`.

The financial phase verifies original payment evidence, partial-payment caches,
active/cancelled allocations, gross customer debits/credits, receipt ownership,
return credits/refunds, directed journal pairs, and source-specific cash IN/OUT.
Original cash attribution requires its posting-time account snapshot; the draft
creator is not assumed to be the confirming collector.
Duplicate or missing inverse entries cannot disappear into a net-zero sum.
Bank, check, and CliQ preserve the repository's distinct clearing accounts;
unknown methods are not silently converted to cash. Refunds require collection
and account provenance within the invoice cohort.

Count-only customer coverage checks stop if other posted invoices, receipts,
returns, or customer transactions would be needed. No unrelated source documents
are fetched to complete that customer. Customer closing comparisons are skipped
when any financial source evidence is blocked. Global warehouse closing,
company/representative cash closing, expenses, settlements, inventory cost/COGS,
and full financial statements remain outside this approval. A PASS cannot
certify those balances, detect deleted evidence absent an independent archive,
or prove that physical delivery occurred.

## Report contract and outcomes

The private JSON includes the snapshot time, actual returned/missing counts,
unique collection counts, exact invoice attribution manifest, source-linked
findings, blockers, per-check expected/actual strings, custody summaries, and
associated financial effects. `difference` is **actual minus expected**. Missing
evidence is a blocker, not an assumed zero. Example comparison format (synthetic
IDs only):

```json
{
  "code": "CUSTODY_OUT",
  "refs": {"invoiceId": "SYNTHETIC_INVOICE", "itemId": "SYNTHETIC_ITEM"},
  "expected": "3.000",
  "actual": "0.000",
  "pass": false
}
```

`summary.shareable.json` removes all operational IDs, quantities and monetary
amounts. It retains environment, status, read time, invoice/record counts,
coverage, comparison count, counts by finding/blocker code, and write/export
flags. An actual **synthetic-only** example is stored in
`output/integrity-audit/jihad_summary_example.synthetic.json`.

| Status / exit | Meaning |
|---|---|
| PASS / 0 | Identity, bounded recorded-source coverage and evidence checks completed; no discrepancy detected in those checks |
| FAIL / 1 | Bounded required evidence completed and one or more confirmed discrepancies exist |
| BLOCKED / 2 | Identity, authentication, permissions, limits, historical evidence or scope prevents a trusted conclusion; partial confirmed findings may coexist |

BLOCKED takes precedence over FAIL. An early CLI/authentication/output failure
may produce only a sanitized stdout blocker and no report files. A run that
reaches auditing preserves its safe partial report unless local output fails.
Never interpret zero retrieved records or zero findings in a BLOCKED run as a
clean production audit. Stop and review the blocker; additional records/access
require separate approval.

## Focused verification

The dedicated loopback emulator tests reuse the previous trusted lifecycle
fixture rather than repeating the complete audit. They exercise real REST
pagination/aggregation/batch reads, snapshot pinning, missing/duplicate/wrong
stock movements, tracking uncertainty, incomplete histories, exact financial
arithmetic, payment methods, ownership and cancellation/refund evidence, scope
and permission failures, mutation rejection, redaction, and private output
guards. The existing reconciliation unit tests run alongside them.

In a **separate test terminal** with a Firestore emulator already listening on
127.0.0.1:8080:

```powershell
Set-Location C:\src\fatoora
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
npm.cmd --prefix functions run test:jihad-readonly
```

Tests seed/reset only `demo-jihad-readonly`. Production execution rejects the
emulator variable. Exact final results and synthetic-only logs are in
`output/integrity-audit/jihad_readonly_verification.json` and `jihad-focused.log`.
No production run is part of these tests.

## Correction review only

Use the prior audit's section 7 approval package: original source and movement
IDs, fixed cutoff, delivery evidence, expected/actual deltas, dependencies,
cost evidence where applicable, invariants and unique compensation identity.
A proven missing sale OUT calls for a separately approved linked custody OUT;
a proven excess movement calls for a linked inverse; wrong-source delivery
requires approved paired location corrections. Financial corrections require
their own source and cash evidence. A cache rebuild requires complete history.
Never replay invoice confirmation, silently overwrite a balance, delete a
posting, or infer an automatic repair from local fixed code. This tool contains
no repair, apply, deployment, or migration mode.
