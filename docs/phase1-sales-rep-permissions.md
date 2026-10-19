# Phase 1: Sales Rep permissions and invoice rules

## Behavior

An active, approved Sales Rep in the company can create/confirm their invoices,
edit/delete their unposted invoice drafts, create/edit quotations and delete
their quotation drafts, convert sent/accepted quotations to invoice drafts,
create receipts, and create/edit/confirm sales-return drafts. Posted invoices,
receipts and returns remain immutable to clients, including admins.

| Area | Before Phase 1 | Phase 1 |
| --- | --- | --- |
| Invoice prices | Non-negative prices, including zero, already supported | Preserved for both roles; no catalog price comparison |
| Discounts | Sales Rep permission flag could block discounts | Both roles may use any numerically valid discount; invoice total must stay positive |
| Quotations/receipts/returns | Legacy flags could block rep operations | Approved role grants operations within existing ownership/financial constraints |
| Quotation deletion | Denied | Own draft only; sent/converted quotations cannot be deleted |
| Return editing | Repository/rules supported drafts but no reopen action | Draft details opens the existing form; edits are persisted before confirmation |
| Quotation conversion | Rep draft inherited warehouse source | Rep conversion explicitly uses own custody; admin conversion retains warehouse source |
| Invoice stock authorization | Backend could accept an existing warehouse-source draft assigned to a rep | Backend explicitly rejects rep confirmation unless source is their own custody |
| Document ownership | Some repository/backend checks also accepted creator UID | Sales document authorization consistently requires assigned `salesRepId` for reps |

Customer creation remains governed by the existing `allowSalesRepCreateCustomers`
setting. Customer opening-balance permissions are unchanged. Other legacy
permission fields remain in the stored settings schema for compatibility but no
longer restrict operational workflows. Their obsolete switches are hidden.
There is no data migration in this phase.

## Validation and transaction boundaries

- Both roles use the same invoice validation: 1–100 lines; finite, positive
  quantities at 3-decimal precision; finite non-negative prices; valid line
  identities/custom metadata; discount between zero and subtotal; tax 0–100;
  and a strictly positive calculated invoice total.
- Catalog-only, custom-only, and mixed invoices are supported. Free lines are
  valid inside a positive-total invoice. No catalog item is required for a
  custom-only invoice.
- Flutter's shared totals service and repositories recompute draft/conversion
  amounts. Its rounding order now matches the trusted backend: round inputs,
  subtotal, discount, taxable amount, tax and total to three decimals.
- Firestore rules enforce identity, company, customer ownership, draft state,
  immutable assignment/creator/source fields, aggregate bounds and line count.
  Every-line numerical/catalog validation and authoritative recalculation remain
  in the trusted confirmation transaction. Rules do not iterate invoice lines.
- Tracked catalog lines consume custody for rep invoices, warehouse stock for
  ordinary admin invoices. Existing admin confirmation of valid rep-source
  drafts remains supported. Repeated item quantities are checked cumulatively.
  Custom/untracked lines create no inventory movements.
- Draft creation/conversion has no inventory, receivable, cash or ledger effects.
  Confirmation posts all existing effects atomically and idempotently. Draft
  saving and confirmation remain separate transactions; failed confirmation
  leaves a draft.
- The return editor preserves the original return identity/creator and uses
  original invoice line pricing and remaining returnable quantities. It does not
  allow arbitrary return prices, over-returns or modification of posted returns.
- No catalog/warehouse/transfer administration, ledger access, administrative
  access, receipt reversal, JoFotara, search or production-data changes are added.

## Customer ownership and future assignment

Phase 1 deliberately keeps `customers.createdByUid` as the customer-access owner.
All current customer queries and indexes are retained. No `assignedSalesRepId`
field, reassignment endpoint, fallback OR condition, or extra read access is
introduced. A rep still needs an owned customer and an own-rep document for
posting. Existing customer-owned statement access is retained.

When admin assignment/reassignment is implemented, it needs one coordinated
ownership migration, not just an extra field:

1. Introduce a canonical assignment field such as `assignedSalesRepId`, separate
   from immutable creation audit fields. Backfill existing rep-created customers
   to that rep; admin-created customers remain unassigned until explicitly
   assigned. Validate active approved same-company assignees.
2. Add a trusted, admin-only, audited assignment operation. Profile updates and
   client writes must not alter ownership. Do not repurpose `createdByUid`.
3. Change customer access checks and queries together: `CustomerRepository`,
   customer picker, `InvoiceRepository`, `QuotationRepository`, statements,
   financial/receivable lists, dashboard reporting and account reporting;
   `customerAllowed`/customer-read/customer-transaction rules; and trusted
   customer, invoice, receipt, return and opening-balance authorization.
   Add the corresponding query indexes and update ownership tests.
4. Define historical access explicitly before enabling reassignment. Invoice,
   quotation, receipt, return, custody and cash `salesRepId` fields identify
   historical sales/collection ownership. Do not rewrite posted financial
   documents to transfer a customer. Define separately who can collect old debt,
   see historical statements or return an old sale. In particular, review
   `canReadCustomerTransaction`, whose owned-customer branch currently exposes
   the customer's complete statement, while other document queries use rep UID.
5. Migrate every customer and all enforcing/query layers before enabling the
   assignment UI. An OR of creator and assignee would retain old-rep access
   after reassignment and is not a safe migration shortcut. Test current/old/new
   owners, unassigned/admin-created customers, cross-company assignments,
   pending/inactive users, historical documents and unchanged cash/custody effects.

## Changed files

- Rules/backend: `firestore.rules`; `functions/src/trusted/common.ts`,
  `confirm_invoice.ts`, `confirm_sales_return.ts`, `create_receipt.ts`.
- Permissions/settings: `lib/core/settings/business_permission_resolver.dart`;
  `lib/features/settings/view/screens/admin_settings_screens.dart`;
  `lib/features/settings/view/widgets/document_settings_form.dart`.
- Invoices: `lib/features/invoices/controllers/invoice_form_controller.dart`;
  `data/models/invoice_model.dart`, `data/repositories/invoice_repository.dart`,
  `data/services/invoice_totals_service.dart` under `lib/features/invoices`.
- Quotations: `controllers/quotation_details_controller.dart`,
  `controllers/quotation_form_controller.dart`,
  `data/repositories/quotation_repository.dart`,
  `view/screens/quotation_details_screen.dart` under `lib/features/quotations`.
- Returns: `controllers/sales_return_details_controller.dart`,
  `controllers/sales_return_form_controller.dart`,
  `data/models/sales_return_model.dart`,
  `data/repositories/sales_return_repository.dart`,
  `view/screens/sales_return_details_screen.dart`,
  `view/screens/sales_return_form_screen.dart` under `lib/features/sales_returns`.
- Labels: `lib/core/localization/quotations_translations.dart` and
  `sales_return_translations.dart`.
- Tests: `test/business_permission_resolver_test.dart`,
  `test/phase1_sales_permissions_test.dart`, `test/phase1_draft_workflows_test.dart`;
  `functions/test/firestore.rules.test.js`, `confirm_sales_return_auth.test.js`,
  `phase1_permissions.test.js`; `functions/package.json` registers the new suite.

## Verification

Executed successfully:

| Check | Result |
| --- | --- |
| Focused Flutter regression suites (8 files) | 58 tests passed |
| `flutter analyze --no-pub` | No issues |
| `npm --prefix functions run lint` | Passed (`tsc --noEmit`) |
| `npm --prefix functions run build` | Passed |
| Combined rules/trusted/callable-auth/Phase 1 emulator suites | 91 tests passed |
| Final rules recheck, including legacy/locked draft regression | 51 tests passed |
| Final Phase 1 backend recheck, including return ownership/partial-posting guards | 9 tests passed |
| `git diff --check` | Passed |

The focused Flutter suites cover effective permissions with legacy flags off,
invoice/custom-line validation, price/discount editing, conversion and ownership,
posted-document locks, draft editing/deletion workflows, existing responsive
quotation/return UI and financial posting calculations.

The Firestore emulator suites cover rules, trusted transactions, callable auth,
both-role invoice validation, free/custom/mixed lines, cumulative custody and
warehouse shortages, warehouse-source rejection for reps, cross-rep/customer
authorization, immutable posted documents, receipts/returns with legacy flags
off, and concurrent/replayed posting without duplicate effects.

Tests use isolated local emulator projects only. No deployment, commit, index
change, ownership migration or production-data operation is part of Phase 1.
The new concurrency test uses the same narrowly scoped retry for the emulator's
intermittent transaction-closed response as the existing trusted test suite;
production transaction/retry behavior is unchanged.
