# Phase 4 correction: legacy customer visibility

Implemented locally. No deployment, commit, production read or production data
modification was performed. All data-writing validation used the local emulator.

## Root cause

The initial Phase 4 change replaced creator-based Rep list queries with
`assignedToUid == uid` AND `assignmentVersion == 1`. Existing customers without
these fields did not match. The same assumption existed in customer pickers,
invoice customer filters, financial receivable pages/top customers and backend
dashboard customer counts/receivables. Admin queries did not acquire an assignment
filter and remained company-wide, subject to their existing active/search filters.

`CustomerModel.effectiveAssigneeUid`, `customerAssignedTo` and Firestore
`ownsAssignedCustomer` already supported creator fallback for point reads and
trusted operations. They were inconsistent with list queries. The customer
`allow list` rule correctly rejected raw creator queries, which can include
customers already transferred away. Merely changing the UI back to a creator
query would either fail the rules or require an unsafe authorization expansion.

The backfill script was dry-run-first and data-preserving, but the initial rollout
incorrectly required it before any legacy customer would appear in the new lists.
That prerequisite is removed.

## Corrected access and pagination

`functions/src/trusted/customer_queries.ts` adds the read-only
`listAccessibleCustomers` callable and shared portfolio query helpers:

- Authenticate the actual caller and require an active, approved Admin/Rep in
  the requested company. Caller-supplied Rep IDs cannot select another identity.
- Query the union of the caller's original-creator candidates and explicitly
  assigned version-1 candidates. This uses indexed queries, not a company-wide
  client download. Firestore deduplicates documents matching both branches.
- Before returning anything, apply the existing authoritative policy: version 1
  uses `assignedToUid`; otherwise use `createdByUid`. Unversioned assignment-like
  metadata never grants access to another Rep. Invalid explicit assignments do
  not fall back to the creator. Admin can read all company customers regardless
  of creator/assignment fields.
- Continue reading bounded candidate batches until a complete authorized page
  and an authorized lookahead are found, or the query is exhausted. Transferred
  records cannot create empty/incomplete pages or a false end-of-results.
- Preserve indexed search, active filters, name ordering, descending balance
  ordering and document-ID tie breakers. Cursors carry scalar sort boundaries
  bound to company, authenticated user and filters; no cursor can bypass access.
- Read authorization, candidates and optional totals in a read-only transaction.
  No customers, assignment metadata or financial records are written by listing.

`AccessibleCustomerQuery` is shared by customer lists/statement lists, the common
customer picker, invoice customer filters, receivable pages/top customers and
existing full authorized export paths. It forwards server cursors and does not
filter ownership from incomplete pages. The common picker therefore fixes invoice,
quotation, receipt and return customer selection together. Admin retains direct
company-wide Firestore queries. Customer details, statements and posting retain
the existing matching creator/versioned authorization policy.

`dashboard_reporting.receivableTotals` now uses the same legacy/current policy
for Rep customer counts and positive receivables. Admin aggregates and historical
sales ownership remain unchanged. No posting, allocation, cash, custody, balance
mutation or financial ledger implementation changed in this correction.

## Rules and migration

Firestore rules keep the secure separation:

- Point customer reads and customer-transaction reads use the effective current
  assignee with creator fallback for legacy records.
- Direct customer list queries require version 1 + authenticated assignee, or
  Admin. Creator-only Rep queries remain denied, even for a currently empty set.
- Legacy/current mixed lists go through the trusted callable, which performs the
  same authorization before forming the page. The rules comment documents this.
- Transfers immediately revoke former-Rep current customer/statement access.
  Historical document read scopes remain the original `salesRepId`.

**Migration is not required to restore legacy visibility.** The existing script
`functions/scripts/backfill_customer_assignment.js` remains optional and unchanged:

```powershell
node functions/scripts/backfill_customer_assignment.js --project=<project-id> --company=<company-id>
```

This defaults to dry-run and validates the entire paginated pass before any apply
writes. Review planned/skipped/unresolved counts and creator/company identity;
resolve all ambiguities before applying. Apply additionally requires `--apply`,
matching `--confirm-project`/`--confirm-company`, and the write limit. Each write
uses an update-time precondition. Repeat the dry-run afterward to verify zero
remaining planned changes and unchanged ownership/financial fields. Repeated
apply is idempotent. Dry-run-first `--rollback` removes only this migration's
metadata on untouched revision-zero records, never a real transfer or history.

The emulator suite exercises dry-run, apply, repeated apply, rollback and a
concurrent-transfer precondition failure. These operations were not run against
any real project.

## Index and rollout requirements

Five specific customer indexes were added to `firestore.indexes.json`, alongside
the retained Phase 4 assignment and existing creator/active/search indexes:

| Fields | Query |
| --- | --- |
| `createdByUid ASC, nameLower ASC` | Legacy branch including inactive customers |
| `searchKeywords CONTAINS, createdByUid ASC, nameLower ASC` | Legacy search including inactive customers |
| `searchKeywords CONTAINS, nameLower ASC` | Admin search including inactive customers |
| `createdByUid ASC, active ASC, currentBalance DESC, __name__ ASC` | Legacy receivable paging with explicit ID tie breaker |
| `active ASC, currentBalance DESC, __name__ ASC` | Admin receivable paging with the same tie breaker |

No index was deployed. Emulator success does not validate production index
readiness. Before releasing this client, publish `listAccessibleCustomers`, the
corrected dashboard reporting and required indexes. Keep all Phase 4 authorization
functions/rules current before enabling transfers. Backfill is not a release
prerequisite. Older creator-query clients remain incompatible with strict Phase 4
list rules and must update; the rules are not weakened to accommodate them.

Legacy-compatible totals read candidate documents in bounded server batches to
apply missing-field fallback accurately. Large portfolios, or many customers
transferred away from one creator, increase read cost/latency; no incomplete page
or approximate total is returned. Existing export paths can still explicitly
retrieve all authorized pages. This change does not add full-company client-side
filtering. Normal cursor pagination remains subject to data changing between
separate requests, while each request uses a consistent read transaction.

## Validation

- 20 assignment/emulator tests: mixed legacy/current records, long excluded
  stretches across pages, no duplicates, Arabic/English searches, active filters,
  Admin access, malformed/unversioned metadata, Rep isolation, legacy receivable
  pages/totals/dashboard, forged scopes/auth, legacy invoice/receipt posting,
  Admin-to-Rep/Rep-to-Admin, and the full existing transfer/financial/migration suite.
- 56 Firestore Rules tests: legacy details/statements, Admin company lists,
  cross-Rep denial before/after transfer, strict direct-query denial and all prior
  rules regressions.
- 74 backend regression tests: trusted transactions, Phase 1 permissions,
  Phase 3 receipt cancellation, financial ledger, search and dashboard reporting.
- 165 Flutter tests: 127 callable paging/decoding/totals/error tests plus customers,
  statements, opening balances, sales flows, receipts/cancellation, financial
  ledger, invoice query contracts and inventory pagination; 38 additional item
  paging, normalized/custody search, stale-response, stock-error and callable
  authentication contract tests.
- Flutter analysis: no issues found. TypeScript build/lint and diff checks passed.

## Changed files

| Area | Files |
| --- | --- |
| Trusted query and export | `functions/src/trusted/customer_queries.ts` (new), `functions/src/index.ts` |
| Dashboard reads | `functions/src/trusted/dashboard_reporting.ts` |
| Shared Flutter query/cursor | `lib/features/customers/data/repositories/accessible_customer_query.dart` (new), `lib/core/data/firestore_query_pager.dart` |
| Lists, pickers and receivables | `lib/features/customers/data/repositories/customer_repository.dart`, `lib/features/invoices/data/repositories/invoice_repository.dart`, `lib/features/financial/data/repositories/financial_repository.dart` |
| Rules documentation and indexes | `firestore.rules` (comment only), `firestore.indexes.json` |
| Tests | `functions/test/customer_assignment.test.js`, `functions/test/firestore.rules.test.js`, `test/accessible_customer_query_test.dart` (new) |
| Reports | This file and corrected `docs/phase4-customer-reassignment.md` |
