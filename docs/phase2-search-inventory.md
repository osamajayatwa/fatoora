# Phase 2 — Search and inventory error handling

Implemented locally on top of the uncommitted Phase 1 working tree. No deployment,
production data writes, or commit was performed.

## Behavior

- Invoice searches normalize case, surrounding/repeated whitespace, Arabic
  diacritics/tatweel, common alef/ya variants, and Arabic/Persian digits. Spaces,
  hyphens, underscores and slashes are equivalent separators for names/numbers.
  Multi-word phrase prefixes match from any word boundary.
- Invoice and warehouse searches continue to query Firestore's `searchKeywords`
  arrays, retaining existing filters, sort fields and document cursors. They do
  not filter only loaded pages or load the full collection into the app.
- Rep custody now has server search and 36-record cursor pages, ordered by
  `updatedAt DESC`, then document ID descending. Search uses existing
  `itemNameSnapshot` and `modelSnapshot` (the catalog item's code); the catalog has
  no separate model field. Only positive custody is listed via derived `hasStock`.
- Warehouse quantities still come from `ItemModel.currentStock`; custody
  quantities come from `RepInventoryBalanceModel.quantity`. Custody KPI totals
  use Firestore count/sum aggregates across the owner's positive balances and
  remain independent of search and pagination. The dashboard reuses that summary.
- All three searches retain the 450ms debounce, two-character minimum, immediate
  Enter search and clear/reset behavior. Generation guards reject stale initial
  and load-more responses, including responses arriving during a newer debounce.
- Rep ownership is forced to the authenticated UID in the repositories; existing
  Firestore Rules independently reject another rep's invoice/custody queries.
- Custody exposes loading, empty, retryable search errors, and inline page errors.
  Failed load-more requests retain the existing rows and cursor for retry.
- Confirmation recognizes only `FirebaseFunctionsException` with code
  `failed-precondition` and the existing exact trusted message shape:
  `Insufficient representative stock for <itemId>.` or
  `Insufficient warehouse stock for <itemId>.` Other errors keep normal handling.
- The form saves the draft and captures its ID before calling the unchanged
  trusted confirmation function. A shortage keeps entered fields visible and
  retries update the same draft rather than creating a second draft.
- GetX `.tr` Snackbars use the requested rep wording exactly:
  - Arabic: **ما معك من هذا الصنف يا فهمان!**
  - English: **You don't have enough of this item in your inventory, genius!**
  - Warehouse: **المخزون المتاح من هذا الصنف في المستودع غير كافٍ.** /
    **There is not enough of this item in warehouse stock.**

## Required preparation before releasing the client

Not performed in this task:

1. Build/publish the search metadata projections (`projectInvoiceSearch`,
   `projectRepInventoryBalanceSearch`, and the updated existing
   `projectItemReportingFields`). Invoice/custody reconciliation re-reads current
   data transactionally, is idempotent, and writes search metadata only.
2. Make the following three new `rep_inventory_balances` collection indexes ready:

   | Fields | Purpose |
   | --- | --- |
   | `salesRepId ASC, hasStock ASC, updatedAt DESC` | Positive custody pages |
   | `searchKeywords CONTAINS, salesRepId ASC, hasStock ASC, updatedAt DESC` | Custody search pages |
   | `salesRepId ASC, quantity ASC` | Positive custody count/sum |

   Existing invoice/item search indexes are reused; none were added for them.
   The implicit document-ID direction follows the last ordered field.
3. Audit/backfill existing search metadata for each company using the new
   paginated maintenance script. Example dry run:

   ```powershell
   node functions/scripts/backfill_search_keywords.js --project=<project-id> --company=default_company
   ```

   Writes require explicit `--apply --confirm-project=<project-id>
   --confirm-company=<company-id>` and a sufficient reviewed `--max-writes`.
   Only `searchKeywords` and custody `hasStock` are changed. Per-document update
   time preconditions prevent overwriting concurrent updates. A conflict stops
   the pass; rerun the dry run before retrying. The default-company pass also
   covers the existing global item catalog. Nothing from this script was run
   against production.

Old records require this backfill for complete multi-word/normalized matching;
custody records without `hasStock` will not appear in the new custody page query.
Deploying projections alone does not retroactively populate unchanged documents.
Projection updates after new backend writes are asynchronous, so custody/search
metadata may briefly lag a posting. Stock validation continues to use the
authoritative quantities inside the existing trusted transaction.

## Validation

- **40 focused Flutter tests passed**: normalization fixtures; invoice filters,
  sorting, debounce and stale responses; warehouse pagination and quantities;
  custody paging, role scope, stale responses, empty/error/retry states; stock
  classification and translated Snackbars for both roles/languages; same-draft
  retry with preserved customer, lines, discount, notes and payment type.
- **53 Flutter regression tests passed**: Phase 1 permissions/draft workflows,
  shared search policy, custom invoice lines, item forms, dashboard layouts and
  trusted callable contracts.
- **11 Node tests passed**: shared normalization fixtures, maintenance parity,
  metadata-only/idempotent backfill and bounded keyword generation.
- **3 local Firestore emulator tests passed**: searches beyond the first page,
  Arabic names/numbers, cursor pages and filters, warehouse/custody quantities,
  count/sum, cross-rep query denial, and metadata-only current-data reconciliation.
- **60 local authorization regression tests passed**: complete Firestore Rules
  suite plus Phase 1 trusted backend permissions.
- `flutter analyze`: **no issues found**. Functions TypeScript build/lint passed.
- Baseline SHA-256 checks confirm Phase 2 did not alter Firestore Rules, trusted
  posting functions/common logic, or invoice financial calculation code. Phase 1
  modifications in those files remain present.

The emulator does not prove production composite-index readiness. No live-device
or production smoke test was performed. Search is bounded ordered phrase-prefix
matching, not fuzzy, arbitrary substring or reordered-word matching: prefixes
up to 80 Unicode characters, full values/suffixes up to 240, and at most 1,024
keywords per document. Very large documents may exhaust the budget for secondary
fields; invoice number and customer fields are generated first. Custody searches
use stored transfer/posting snapshots, not a live join to renamed catalog items.

## Phase 2 changed files

Paths below are changes relative to the Phase 1 working tree, not the last commit.

| Area | Files |
| --- | --- |
| Search protocol | `lib/core/search/normalized_search.dart` (new), `lib/core/search/server_search_policy.dart`, `functions/shared/search_keywords.js` (new), `functions/shared/search_keywords.d.ts` (new) |
| Invoice queries/model | `lib/features/invoices/controllers/invoices_list_controller.dart`, `lib/features/invoices/data/models/invoice_model.dart` |
| Draft confirmation/errors | `lib/features/invoices/data/repositories/invoice_repository.dart`, `lib/features/invoices/controllers/invoice_form_controller.dart`, `lib/features/invoices/controllers/invoice_error_mapper.dart`, `lib/core/localization/invoices_translations.dart` |
| Warehouse items | `lib/features/items/data/models/item_model.dart`, `lib/features/inventory/controllers/inventory_dashboard_controller.dart` |
| Custody | `lib/features/rep_inventory/controllers/rep_inventory_controllers.dart`, `lib/features/rep_inventory/data/models/rep_inventory_balance_model.dart`, `lib/features/rep_inventory/data/repositories/rep_inventory_repository.dart`, `lib/features/rep_inventory/view/screens/rep_inventory_screens.dart`, `lib/features/financial/controllers/sales_rep_dashboard_controller.dart` (custody KPI loading only) |
| Backend metadata/indexes | `functions/src/trusted/operational_search_projection.ts`, `functions/src/index.ts`, `firestore.indexes.json` |
| Maintenance/test commands | `functions/scripts/backfill_search_keywords.js` (new), `functions/scripts/backfill_item_search_fields.js`, `functions/scripts/invoice_list_fields_common.js`, `functions/package.json` |
| Flutter tests | `test/normalized_search_test.dart` (new), `test/custody_search_test.dart` (new), `test/paged_search_race_test.dart` (new), `test/invoice_stock_error_test.dart` (new), `test/inventory_phase4_test.dart`, `test/fixtures/phase2_search_cases.json` (new) |
| Backend tests | `functions/test/search_keywords.test.js` (new), `functions/test/search_inventory.test.js` (new) |
| Report | `docs/phase2-search-inventory.md` (new) |
