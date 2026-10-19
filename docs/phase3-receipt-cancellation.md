# Phase 3 — Safe receipt cancellation

Implemented locally on top of Phases 1–2. No deployment, commit, or production
data changes were performed.

## Reversal strategy

`cancelReceipt` calls `cancelReceiptTransaction` in
`functions/src/trusted/cancel_receipt.ts`. One Firestore transaction:

1. Reads the authenticated user's current profile and requires an active,
   approved Admin in the requested company. Client-supplied actor fields are
   never trusted. A trimmed reason of 1–500 characters is required.
2. Loads the original receipt, customer transaction, invoice allocation map,
   allocated invoices, financial ledger entries and original cash movement.
   Missing/inconsistent evidence causes a structured `failed-precondition`
   error with no writes. Existing status-less trusted receipts are treated as
   posted, provided their financial evidence is complete.
3. Adds the receipt amount back to the customer's signed `currentBalance` and
   subtracts it from `totalPaid`. Customer credit is a negative signed balance;
   there is no separate credit bucket to overwrite.
4. Subtracts each original allocation from the invoice's current `paidAmount`
   and adds it to `remainingAmount`. Other payments remain intact. Recomputes
   payment status and `hasReceivedPayment`, removes the receipt from active
   `receiptIds`, retains its ID in `cancelledReceiptIds`, and updates
   `lastReceiptId` to the last remaining active receipt. The receipt's original
   allocation snapshot remains unchanged.
5. Appends a linked customer debit reversing the original customer credit.
   For cash, appends an out movement against the **original collection account**
   and updates that account's materialized cash balance. A rep collection is
   reversed from that rep's cash, even though the cancellation actor is Admin.
   Bank/check/CliQ collections reverse their original bank/clearing ledger
   accounts and do not introduce cash movements.
6. Creates deterministic Financial Ledger inverse entries, swapping debit and
   credit accounts and negating the original metrics. Their `type` remains
   `receipt`, so receipt-filtered ledger totals include the inverse; their
   component, description and links clearly identify cancellation. The original
   ledger entries are untouched. Reversals are booked on the cancellation date.
7. Marks the preserved receipt `status: cancelled`, recording reason, actor UID,
   name and role, timestamp, cancellation version, reversal IDs, and immutable
   inverse snapshots used by historical ledger rebuilds.

All reads finish before writes. Receipt, customer, invoice and cash-balance reads
participate in Firestore transaction conflict retries. Deterministic reversal IDs
use create-only writes. Once committed, repeated cancellation calls return
`alreadyCancelled: true` without changing the winning actor, reason or effects.

## Safety restrictions and limits

- Rejects cancellation of allocated invoices with any recorded sales return.
  This is conservative even if the return predates the receipt.
- Rejects cash cancellation if any outflow in the original account was posted
  at or after collection, including spending, settlement, refunds or another
  cancellation. Replenishing the account does not bypass that dependency check.
  Missing/reconciling cash balances and insufficient funds also block reversal.
- Noncash collection accounts have no independent settlement subsystem here.
  Any recorded Financial Ledger outflow from that bank/clearing account blocks
  cancellation, conservatively including earlier/unrelated outflows. External
  bank/check/CliQ activity outside Fatoora cannot be verified by this feature.
- A legacy receipt that produced customer credit can be reversed while the
  credit is unchanged and has no subsequent customer transactions. Credit use
  or later customer activity blocks cancellation. Phase 1's current prohibition
  on new receipts exceeding receivables is unchanged.
- Supports up to **100 allocated invoices** and **101 owner ledger groups** per
  receipt. Larger or incomplete legacy records require review; the function
  does not guess missing financial history or perform a partial reversal.
- Canonical customer/cash/ledger writes are atomic. Existing asynchronous ledger
  search, summary and account-activity projections update through the existing
  triggers, so derived reporting can briefly lag the transaction.
- Dashboard/document reports exclude cancelled receipt amounts in their
  original receipt-date period. The Financial Ledger and customer statements
  preserve the original event and show the inverse on the cancellation date.
- Historical ledger rebuilds include both original and inverse entries, using
  the receipt's immutable reversal evidence, including cancellation-only date
  ranges. Existing rebuild safeguards for unresolved legacy ownership remain.

## UI and exports

- Admin-only Cancel actions on mobile cards, desktop rows and receipt details
  share the same reason/confirmation dialog and trusted operation.
- Sales Reps can still create receipts and view their authorized records, but
  have no cancellation action. Repository and backend authorization independently
  reject cancellation attempts. Existing Security Rules deny direct receipt,
  movement and ledger writes to both roles.
- Lists/details label cancelled receipts. Details show actor, reason, timestamp
  and a historical-data explanation. Repeat cancellation is unavailable.
- Historical PDF export remains available and prominently marks cancellation,
  with actor/reason/date and the original payment balance clearly labelled.
- Operational Excel keeps cancelled receipts as historical rows with zero
  effective amount/allocation. Appended columns show status, original amount,
  cancellation reason, actor and date. Existing columns retain their positions;
  the Receipts sheet expands from 17 to 22 columns.
- Customer statements and cash reports include appended inverse movements;
  their original financial history is never deleted or overwritten.

## Required release preparation — not performed

Publish the new callable and cancellation-aware dashboard reporting together with
the client. Publish these **five** new collection indexes from
`firestore.indexes.json` and wait until they are ready:

| Collection | Fields, all ASC |
| --- | --- |
| `customer_transactions` | `customerId, createdAt` |
| `cash_movements` | `cashAccount, direction, createdAt` |
| `cash_movements` | `cashAccount, direction, salesRepId, createdAt` |
| `receipts` | `status, receiptDate, amount` |
| `receipts` | `status, salesRepId, receiptDate, amount` |

Existing ledger projections are reused. No Security Rules changes or receipt
status backfill are needed. The emulator does not validate production composite
index readiness. No production or live-device smoke test was performed.

## Validation

- **15 focused emulator tests passed**: company cash; multiple invoice owners;
  partial allocations; unallocated opening receivables; rep cash; unused/consumed
  legacy credit; retained later receipts/initial payments; bank/check/CliQ;
  repeated cancellation; unauthorized/cross-company/inactive callers; reason
  validation; inconsistent history/returns; settled cash after replenishment;
  concurrent cancellations, posting and settlement; direct-write rule denial;
  dashboard totals, ledger projections and a safe dry-run historical rebuild.
- **79 backend regression tests passed**: complete Firestore Rules suite, Phase 1
  trusted permissions, ledger mapping/projection unit tests, and Phase 2 search
  keyword tests.
- **41 Flutter receipt/export tests passed**: dialog validation, both languages,
  role/action visibility, duplicate-request guard, dependency error handling,
  legacy model compatibility, cancelled PDF/Excel and existing receipt/report UI.
- **73 Flutter regression tests passed**: customer statements, cash calculations,
  ledger UI/export, Phase 1 permissions/workflows and Phase 2 searches/stock errors.
- `flutter analyze`: **no issues found**. TypeScript lint/build passed.
- Baseline hashes confirm unchanged receipt creation, invoice/return posting,
  cash settlements/helpers, core ledger writer/mappings and Firestore Rules.

Local emulator command: `npm --prefix functions run test:receipt-cancellation`
with `FIRESTORE_EMULATOR_HOST` pointing at a local emulator. Test fixtures use
an isolated test project, never production.

## Changed files relative to Phase 2

| Area | Files |
| --- | --- |
| Trusted cancellation | `functions/src/trusted/cancel_receipt.ts` (new), `functions/src/index.ts` |
| Reports/audit/maintenance | `functions/src/trusted/dashboard_reporting.ts`, `functions/src/audit/entity_audit_config.ts`, `functions/src/maintenance/rebuild_financial_ledger.ts` |
| Indexes/test command | `firestore.indexes.json`, `functions/package.json` |
| Receipt state/API | `lib/features/receipts/data/models/receipt_model.dart`, `lib/features/receipts/data/repositories/receipt_repository.dart` |
| Receipt controllers | `lib/features/receipts/controllers/receipt_details_controller.dart`, `lib/features/receipts/controllers/receipts_list_controller.dart`, `lib/features/receipts/controllers/receipt_error_mapper.dart` |
| Receipt UI | `lib/features/receipts/view/screens/receipt_details_screen.dart`, `lib/features/receipts/view/screens/receipts_list_screen.dart`, `lib/features/receipts/view/widgets/receipt_presentation.dart`, `lib/features/receipts/view/widgets/receipt_cancel_dialog.dart` (new) |
| Translations/PDF | `lib/core/localization/receipts_translations.dart`, `lib/core/pdf/app_pdf_localization.dart`, `lib/features/receipts/data/services/receipt_pdf_service.dart` |
| Operational totals/export | `lib/features/financial/data/repositories/financial_repository.dart`, `lib/features/operational_report/data/models/operational_report_data.dart`, `lib/features/operational_report/data/services/operational_report_excel_service.dart` |
| Tests | `functions/test/cancel_receipt.test.js` (new), `test/receipt_cancellation_test.dart` (new), `test/receipts_phase8_test.dart`, `test/operational_report_test.dart` |
| Report | `docs/phase3-receipt-cancellation.md` (new) |
