# Customer reassignment and return verification

> Release review: [staging candidate and current gates](reassignment-staging-release.md)
> supersedes the confirmed-only read condition and the original 64-index proposal
> below. Posted electronic lifecycle states are covered; final additions are 32.

Verified locally on 2026-11-08. No production reads, deployment, historical
corrections or cloud writes. Existing staging work in the workspace was preserved.

## Findings and fixes

| Area | Behavior before changes | Result |
| --- | --- | --- |
| Transfer | Trusted transaction changes assignment metadata and appends an audit event; financial documents and balances remain untouched. | Preserved and regression-tested. |
| Invoice history | Rep queries always filter by the original `salesRepId`. Rules and repository detail checks also reject other sellers. This was the earlier documented policy, not a missing backfill or cache issue. | The existing customer filter includes the assigned customer's confirmed, financially posted invoice history. Detail reads use the same assignment policy. |
| Statement | Current assignment authorizes the complete customer financial history. Former assignee loses access. | Preserved. Customer/statement reads now require the server; denied page reads clear retained statement/list data. |
| Sales attribution | Invoice and return sellers are independent of customer assignment. Dashboard queries use the seller and each document's actual date. | Preserved. Return creator/approver and current customer owner cannot override the original invoice seller. |
| Refund attribution | If the new rep collected an old invoice, refunds correctly debit that rep's cash, but the ledger tags cash-out metrics with the original seller. The refund movement also uses the wrong rep name. | Refund ledger ownership and names follow the verified collecting cash account. The separate sales reversal stays with the invoice seller. Posting and guarded rebuild mappings agree. |

Both invoice-history denial and incorrect refund ledger ownership were reproduced
with failing regression tests before fixes. The prior focused baseline had 107
passing tests, demonstrating missing coverage.

## Final contract

- Default invoice lists and sales reports remain seller-scoped. Selecting a
  customer in the existing invoice filter adds posted history without transferring
  sales. The rep's own drafts remain visible; other sellers' drafts stay protected.
- Read access grants no edit, deletion, confirmation, electronic-submission or
  return permission. Original sellers retain their historical invoices and totals,
  but lose current customer/profile/statement access. Further reassignment revokes
  borrowed history access on subsequent server reads, including cursor pages.
- Cross-seller historical returns still require Admin. Backend document ownership
  and current customer checks remain intact. The invoice detail screen disables
  the ineligible return action.
- Invoices retain seller, source lines, prices and invoice date. Only normal
  return/payment projection fields change. Returns and ledger reversals use
  `returnDate`; refunds add no second sales reversal.
- Returns reduce outstanding receivables first, then refund or credit the paid
  portion. Cash follows its verified collecting account. Stock returns to the
  original warehouse/custody source. Transfer itself changes none of these values.
- No customer-history repository cache was found. The user-profile cache contains
  no customer assignment. Server reads prevent stale offline cache fallback from
  authorizing access; denied list/statement reads clear retained controller data.
  Already downloaded data cannot be erased remotely.

## Tests and verification

- Full backend suite: **682 passed**, including Rules, assignment races,
  idempotency, trusted authentication/posting, receipt cancellation, inventory,
  reporting projections, reconciliation and maintenance safeguards.
- Final focused posting suite: **7 passed**, including the subsequently added
  mixed-collector refund rejection case. The expanded Rules history/revocation
  regression also passed after adding draft-filter coverage.
- Related Flutter suite: **117 passed**, including query scope/server reads,
  assignment, statements, denied-page cleanup, permissions, receipts, returns,
  ledger/dashboard models and invoice arithmetic.
- TypeScript build/lint, changed-area Flutter analysis and `git diff --check`
  passed. Manifest tests cover both history query branches across existing sort
  directions and search; 64 scoped indexes were added.
- Synthetic cases cover Admin/company and rep invoices, transfers, new sales,
  partial/full/excess/replayed returns, cash refunds, customer credit and mixed
  collectors. Statements reconcile to customer balances; account debits/credits
  and cash balances reconcile; seller sales/cash metrics and replayed reporting
  projections reconcile to company net sales. A read-only rebuild audit accepts
  the new cross-collector refund mapping.

Firestore tests used a separate Java emulator on `127.0.0.1:8188`, started with
`demo-fatoora-workflows`, and synthetic test namespaces only. The new posting
suite uses `demo-fatoora-reassignment-returns`. No production credentials, catalog
exports or production bootstrap scripts were used. Functions transaction/callable
handlers ran directly against this emulator. Deployed callable transport and
live-device behavior were not tested.

Reproduce against that dedicated running emulator:

```powershell
npm.cmd --prefix functions run build
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8188'
node functions/scripts/run_integrity_tests.js
node --test functions/test/reassignment_returns.test.js
```

Logs: `build/workflow-baseline.log`, `build/workflow-regression-before.log`,
`build/workflow-visibility-before.log`, `build/workflow-backend.log`,
`build/workflow-focused.log`, `build/workflow-visibility-after.log`,
`build/workflow-flutter.log`, `build/workflow-analyze.log`.

## Remaining limits and accounting risks

- Existing historical refund ledger attribution remains unchanged. A future audit
  may find conflicts with the corrected mapper; the guarded rebuild reports these
  rather than overwriting posted entries.
- Cash refunds spanning collecting accounts remain blocked atomically; customer
  credit is supported. Refunds require verified evidence and sufficient cash in
  the original collecting account, including after settlements.
- Missing legacy seller, customer, posting or indexed sort fields need explicit
  review. No identities were guessed or backfilled.
- Assigned portfolio receivables differ from seller-filtered historical ledger
  activity. Active-rep dashboard rows exclude Admin/inactive sellers while company
  sales include their invoices. Summing these rows does not reconcile all company
  activity. Existing active-customer receivable filtering remains.
- Projections are asynchronous. Emulators do not establish deployed index
  readiness; any future release needs coordinated Rules, indexes, client and
  Functions changes. No release was performed.
- Existing operational sales metrics use invoice gross totals, including tax.
  These mappings do not establish complete tax-liability, inventory valuation or
  COGS accounting. This work does not implement the next double-entry phase.
