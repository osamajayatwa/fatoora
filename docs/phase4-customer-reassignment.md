# Phase 4 — Customer reassignment

Implemented locally on top of Phases 1–3. No deployment, commit, or production
data modification was performed. Maintenance commands were exercised only against
the isolated local Firestore emulator test project.

## Ownership and financial invariants

| Field/scope | Meaning |
| --- | --- |
| Customer `createdByUid/Name/Role`, `createdAt` | Original creator; preserved across transfers |
| Customer `assignmentVersion: 1`, `assignedToUid/Name/Role` | Current responsible Admin or Sales Rep |
| Customer `assignmentRevision` | Compare-and-set revision, incremented by each real transfer |
| Invoice/quotation/receipt/return `salesRepId` | Original document ownership; never changed by reassignment |
| Invoice `salesRepId` | Historical sales attribution; independent of current customer assignment |

`reassignCustomerTransaction` updates **only the customer assignment metadata and
updatedAt**, and appends an immutable `customer_assignment_events` record in the
same transaction. It does not read or write invoices, quotations, receipts,
returns, customer financial movements, cash, custody, or ledger entries.

The callable verifies the current authenticated Admin, company, target user's
active/approved status and Admin/Rep role, reason, expected current assignee and
revision. Deterministic operation keys make retries idempotent. Competing transfers
cannot silently overwrite one another. Events preserve previous/new assignees,
actor, reason, revision, timestamp and whether the source was legacy ownership.

New customers are assigned to their actual creator by the existing trusted
creation function. Assignment payloads supplied to ordinary create/update profile
calls cannot override the trusted assignment or original creator.

## Access and historical reporting

- Customer lists, pickers, statements, current receivables, profile updates,
  opening balances, invoice/quotation creation/conversion, receipt posting and
  return confirmation consistently authorize the current assignment.
- Rep customer list queries require both `assignedToUid == auth.uid` and
  `assignmentVersion == 1`. The rules do not authorize a creator-only list query.
- The previous Rep loses the current customer profile and customer statement,
  including customer transactions they originally posted. The currently assigned
  Rep can read the **complete customer statement** needed to reconcile debt.
- Direct historical invoice, quotation, receipt and return access remains
  constrained by each document's original `salesRepId`. Assignment never grants
  another Rep's full historical documents. Historical snapshots already contained
  in the previous Rep's own documents remain intact.
- Draft/status/delete mutations also check current customer access in Rules.
  Old drafts stay with their original owner; they are not adopted by the new Rep.
  Admin can resolve them. A former Rep cannot confirm a stale invoice draft.
- Sales totals, sales KPIs and historical exports still aggregate immutable
  invoice/return ownership. Reassignment does not change previous sales totals.
  New invoices created by the new Rep retain that Rep's identity and normal
  inventory source. Admin-created invoices retain the existing Admin behavior.
- Current portfolio/customer count/receivable KPIs follow assignment. Historical
  sales attribution does not. Rep-filtered ledger activity and current assigned
  customer debt are distinct scopes; no synthetic debt-transfer entries are posted.
- Admin continues to access all company records. Cross-company targets and
  inactive/pending users are rejected. Clients cannot directly write assignment
  metadata or assignment event history.

## Receipts, allocations, returns and balances

The previous receipt allocator filtered invoices to the collecting Rep. That
would have reduced the transferred customer's balance without paying their old
invoices. After authorizing current assignment, the trusted allocator now reads
all posted invoices for that **customer**, in the existing due-date order.

- A new Rep can collect old debts and make partial payments across old and new
  invoices. Amount limits, arithmetic and posting transactions remain intact.
- Authorized collection updates only the normal invoice payment/allocation
  counters. It does not change invoice owner, sales amount, original financial
  postings or original inventory source.
- A Rep collection is owned by the collecting Rep and enters that Rep's cash
  account. Collecting old debt contributes **zero new sales**. Admin collection
  uses company cash; new receipt visibility follows the versioned current
  customer assignee, preventing an old invoice owner from seeing a new receipt's
  current customer snapshot merely because their invoice was paid.
- Financial Ledger ownership groups are stored immutably with each new receipt.
  For a transferred Rep collection, new collection/cash activity belongs to the
  collector. Existing same-owner/Admin ledger mapping is retained. Historical
  ledger rebuilds use that posting snapshot, not a later customer's assignee.
- Assigned-customer receivable reporting uses the full customer ledger after
  checking assignment, so a transfer cannot drop prior debt from the new Rep's
  balance. Customer statements also include the full financial history.
- Receipt allocation references include the invoice identifiers/numbers and
  payment amounts necessary for payment evidence. They do not grant permission
  to read another Rep's invoice document, lines or unrelated sales records.
- Returns require both current customer assignment and original invoice access.
  The new Rep can return their own new invoices. **Admin handles returns against
  another Rep's historical invoices**. Such returns keep the original invoice's
  sales attribution and inventory/cash source; they do not move custody to the
  customer's new Rep.
- Phase 3 receipt cancellation remains Admin-only and reverses the original cash
  account and stored financial evidence, including receipts collected after a
  customer transfer. The cancellation implementation itself is unchanged.

## Legacy migration and rollback

Only **version 1** assignment is authoritative. Point reads and trusted operations
on legacy customers retain the original creator-based access policy. Unversioned
assignment-like fields never silently grant another Rep access. Ambiguous
unversioned `assignedToUid` records are refused for automatic migration/transfer
and reported for explicit review.

Paginated assignment queries cannot coalesce missing legacy fields. Therefore,
**the reviewed backfill is required before releasing the new Rep list queries**.
Unmigrated records are intentionally omitted from those queries, rather than
broadening access or loading the full collection in Flutter.

Dry run, with explicit project and company:

```powershell
node functions/scripts/backfill_customer_assignment.js --project=<project-id> --company=<company-id>
```

Apply additionally requires `--apply --confirm-project=<project-id>
--confirm-company=<company-id>` and a reviewed sufficient `--max-writes`.
The script validates the complete paginated pass before writing. It copies the
**existing creator UID exactly**, validates creator/company identity, marks the
migration and preserves all original fields, balances and updatedAt. Missing or
ambiguous identities stop an apply pass before any planned writes. Each write
has an update-time precondition, so a concurrent transfer cannot be overwritten.
A conflict during the write pass can leave a safe partial migration; rerun a
dry run before resuming. Repeated application is idempotent.

Rollback is also dry-run-first:

```powershell
node functions/scripts/backfill_customer_assignment.js --project=<project-id> --company=<company-id> --rollback
```

Applying rollback requires the same project/company confirmations. It removes
only metadata added by this migration, only while revision is zero, the assignee
still equals the original creator, and no real transfer event exists. It refuses
to undo real transfers. Rollback never restores/deletes financial data because
migration never changes it. After real transfers, any business reversal must use
a new Admin reassignment event, not a metadata rollback.

## Release/index requirements — not performed

Use a controlled cutover:

1. Publish the updated existing authorization/posting/reporting functions while
   leaving the **new `reassignCustomer` callable unpublished**. Legacy ownership
   is still unchanged at this stage. Prepare/verify indexes and review migration.
2. Backfill each company, resolve reported legacy issues and verify coverage.
   Coordinate the client query change and strict list rules in a maintenance
   window. Creator-only clients cannot continue using the strict new list rules.
3. Verify all existing authorization functions, Rules, queries and clients are
   current, then publish `reassignCustomer` last. Do not enable transfers while
   older creator-based backend authorization remains deployed.

Six new `customers` collection indexes are included. `V` below is
`assignmentVersion ASC`, `U` is `assignedToUid ASC`; other equality fields are ASC:

| Fields | Query |
| --- | --- |
| `V, U, nameLower ASC` | All assigned customers |
| `V, searchKeywords CONTAINS, U, nameLower ASC` | Search including inactive records |
| `V, U, active, nameLower ASC` | Active lists/pickers |
| `V, searchKeywords CONTAINS, U, active, nameLower ASC` | Active search/pickers |
| `V, U, active, currentBalance ASC` | Current portfolio aggregates |
| `V, U, active, currentBalance DESC, __name__ ASC` | Receivable pages/top customers |

Existing historical document/receipt allocation indexes are reused. Old indexes
are retained for controlled rollback. The emulator does not verify production
index readiness. No live-device or production smoke test was performed.

## Validation

- **15 assignment emulator tests passed:** Admin→Rep, Rep→Rep, Rep→Admin,
  creator/financial preservation, authorization, stale/concurrent operations,
  legacy policy, migration dry-run/apply/idempotency/rollback, migration conflict
  protection, new operations, historical debt/partial payments, Admin/new Rep
  collection scope, Phase 3 cancellation, historical returns, exact sales KPIs,
  complete customer statement/projected debt and collection/transfer races.
- **55 Rules tests passed:** direct cross-rep denial; unchanged historical
  document ownership; versioned query scope; customer statement access;
  invoice/quotation creation; sorted cursor pagination across transferred
  customers; legacy ambiguity and existing authorization regressions.
- **66 backend regression tests passed:** trusted posting transactions, Phase 1
  permissions, Phase 3 cancellation, ledger mapping/projections and Phase 2 search.
- **143 Flutter tests passed:** 103 customer/assignment/statement/opening balance,
  quotation/return/receipt/ledger and Phase 1–3 tests, plus 40 Phase 2 search,
  custody, paging and stock-error tests. Both dialog languages are covered.
- Flutter analysis: **no issues found**. TypeScript lint/build passed.
- Baseline hashes verify unchanged core ledger/cash writers and mappings,
  inventory/custody posting, cash settlements and Phase 3 cancellation logic.

## Remaining limits

- Assignment changes revoke new server access; they cannot erase previously
  downloaded/offline data or immutable snapshots in authorized historical records.
- Statements expose the assigned customer's financial history, while full
  historical sales documents remain separately protected. This is necessary for
  accurate debt collection; it is not ownership transfer of those documents.
- Cross-rep historical returns need Admin. Old drafts are not automatically
  reassigned. Some existing historical action buttons may receive permission
  errors after transfer when their current-customer mutation check fails.
- Historical assignment-period portfolio analytics are not reconstructed; the
  assignment journal supplies audit history and current portfolio follows the
  current assignment. Historical sales remain document-based.
- Existing financial allocation/transaction-size limits still apply to very
  large customer histories. Existing ledger reporting projections remain
  asynchronous; canonical posting and reassignment transactions are atomic.

## Changed files relative to Phase 3

| Area | Files |
| --- | --- |
| Assignment API | `functions/src/trusted/customer_assignment.ts` (new), `functions/src/index.ts` |
| Customer/profile authorization | `functions/src/trusted/customer_profiles.ts`, `functions/src/trusted/post_opening_balance.ts`, `functions/src/trusted/update_opening_balance.ts` |
| Document authorization/collection | `functions/src/trusted/confirm_invoice.ts`, `functions/src/trusted/confirm_sales_return.ts`, `functions/src/trusted/create_receipt.ts` |
| Reporting/audit/rebuild | `functions/src/trusted/dashboard_reporting.ts`, `functions/src/trusted/financial_ledger_account_reporting.ts`, `functions/src/audit/entity_audit_config.ts`, `functions/src/maintenance/rebuild_financial_ledger.ts` |
| Rules/indexes/commands | `firestore.rules`, `firestore.indexes.json`, `functions/package.json` |
| Migration | `functions/scripts/backfill_customer_assignment.js` (new) |
| Customer model/API/controllers | `lib/features/customers/data/models/customer_model.dart`, `lib/features/customers/data/repositories/customer_repository.dart`, `lib/features/customers/controllers/customer_details_controller.dart`, `lib/features/customers/controllers/customer_error_mapper.dart` |
| Customer UI/localization | `lib/features/customers/view/widgets/customer_reassignment_dialog.dart` (new), `lib/features/customers/view/screens/customer_details_screen.dart`, `lib/features/customers/view/screens/customers_list_screen.dart`, `lib/features/customers/view/widgets/customer_list_components.dart`, `lib/core/localization/customers_translations.dart` |
| Dependent Flutter scopes | `lib/features/invoices/data/repositories/invoice_repository.dart`, `lib/features/quotations/data/repositories/quotation_repository.dart`, `lib/features/financial/data/repositories/financial_repository.dart` |
| Tests | `functions/test/customer_assignment.test.js` (new), `functions/test/firestore.rules.test.js`, `test/customer_assignment_test.dart` (new) |
| Report | `docs/phase4-customer-reassignment.md` (new) |
