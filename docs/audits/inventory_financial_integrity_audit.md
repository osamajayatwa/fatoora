# Inventory and financial integrity audit

Audit date: **2026-11-02, Asia/Amman**. Repository: **C:\src\fatoora**.
Reference only: `C:\src\fatoora_platform`; no changes were made there.

## Decision and scope

| Gate | Result | Evidence and limit |
|---|---|---|
| Corrected paths on isolated fixtures | PASS | 223 backend tests, 423 Flutter tests; zero failures or skips in the final runs |
| Independent reconciliation | PASS, synthetic only | 51 comparisons across source events, stock, custody, cash, customer balances, ledger accounts, and summary totals; zero discrepancies/warnings |
| Static analysis and release web compilation | PASS | TypeScript build; Flutter analysis with no issues; web release build with `FATOORA_ENV=test` |
| Jihad's historical invoice and affected production records | BLOCKED | No invoice ID was supplied. Automatic approval review rejected the proposed bounded, read-only production lookup. No production records were read |
| Complete accounting/operational acceptance | FAIL / incomplete | Period control, source-cost inventory accounting, some reversals, and several requested operations are not implemented; live balances and deployment versions remain unverified |

Passing fixtures does **not** certify the historical database, the deployed code,
all reporting projections, or complete financial statements. The production
project alias is `fatoora-6b192`, established from `.firebaserc` and
`docs/firebase-environments.md`. No deployment, commit, production repair,
migration, opening-balance change, or historical ledger rewrite was performed.

No applicable `AGENTS.md` was found in this repository or its ancestor paths.
The initial working tree was clean. Existing architecture, trusted transactions,
security rules, tests, report builders, and maintenance safeguards were reviewed
before changes. `.audit_mutations.txt` contains older code references and was
not treated as evidence of current behavior.

## 1. Invoice lifecycle and the Jihad report

### Current path

1. `invoice_form_controller.dart` builds an editable draft. The repository
   normalizes identity, creator, representative, totals, and stock source.
   A new representative draft uses `salesRep` and that user's custody ID;
   an administrator's draft uses `companyWarehouse`. Updates preserve the
   original source and creator. Quotation conversion creates a draft only.
2. Client rules permit draft CRUD with current customer access. They prohibit
   direct confirmed invoice, stock, customer-balance, cash, and ledger writes.
3. `confirmInvoiceTransaction` reads the approved user's profile, persisted
   draft, current customer assignment, and catalog records. It recalculates
   totals and validates the persisted stock source independently of the client.
4. Tracked catalog lines create deterministic OUT movements and update either
   warehouse stock or representative custody, including repeated catalog items
   on separate invoice lines. Custom lines intentionally create no stock effect.
5. The same Firestore transaction posts the full customer debit, the initial
   payment credit, actual cash inflow, financial ledger pairs, and posting flags.
   The customer balance change is `grandTotal - initialPaidAmount`.
6. An already fully posted invoice returns `alreadyPosted`; mixed/partial flags
   and existing stock/customer/cash effects fail closed. New financial ledger
   rows now use create preconditions, so an existing row aborts the entire commit.
7. Search, item reporting, ledger summaries, account activity, and audit events
   are asynchronous projections/triggers. They must be distinguished from the
   authoritative transaction. Custody list queries depend on `hasStock` metadata.
8. Receipts subsequently update `paidAmount`/`remainingAmount`; those mutable
   fields must never be mistaken for the initial payment when reconstructing
   collections. New confirmations retain `initialPaidAmount`,
   `initialCashAccount`, and `items[].stockTrackedAtPosting` for provenance.

### Verified symptom-compatible defect

The original `buildInvoiceInventory` skipped every catalog item whose current
`trackStock` flag was not `true`. Catalog rules allowed an administrator to
disable tracking without reconciling the item's existing warehouse or custody
balances. A synthetic representative with 10 units in custody, an untracked
catalog item, warehouse quantity zero, and a three-unit invoice could therefore
confirm the invoice and financial effects with **no custody OUT movement**.

`disabled catalog tracking cannot silently bypass existing custody` failed
against the pre-guard compiled implementation: the expected rejection did not
occur. It now passes: confirmation fails without financial/stock effects until
the inconsistent tracking policy is reviewed. Catalog edits can no longer
change existing tracking or warehouse identity. The edit screen explains the
restriction and directs quantity corrections to Inventory adjustments.

This is a verified code defect and reproduction of the reported symptom.
**It is not a verified explanation of Jihad's particular invoice.** The normal
synthetic representative sale deducts custody 10 -> 7, leaves warehouse stock at
20, posts cash 10 and receivable 20, and posts only once on replay.

### Historical investigation still needed

The proposed lookup would identify Jihad from existing profiles, then inspect a
bounded set of his invoices, custody balances, and movements using the existing
local Firebase login. Automatic approval review rejected it because explicit
approval for this sensitive production scope was required. The rejected command
did not execute. No invoice identifier, affected live quantity, or repair amount
has been invented.

After approval, establish the actual profile UID/company, invoice ID and status,
creation/confirmation times, source fields, item snapshots, tracking policy at
posting, movement IDs, movement history, and balance projection. Distinguish:

- Draft or failed confirmation: no finalized deduction is expected.
- Correct custody OUT but unchanged visible balance: compare balance document,
  `lastMovementId`, `hasStock`, trigger delivery, query scope, and cached UI.
- Warehouse OUT instead of custody OUT: establish the persisted source and
  actual physical delivery source before proposing a paired correction.
- Confirmed sale with no OUT: establish whether it was custom/untracked,
  affected by the tracking defect, posted by older code, or incompletely migrated.
- Duplicate/partial movements or flags: reconstruct all source effects before
  proposing corrections. Current code is not proof of the deployed historical code.

## 2. Transaction flow register

Positive customer balance means the customer owes the company; negative means
customer credit. `Dr`/`Cr` describe existing financial ledger mappings, not a
complete chart of accounts or inventory valuation policy.

| Flow / trusted boundary | Inventory effect | Cash / customer effect | Current accounting effect and control |
|---|---|---|---|
| Item creation / `createItem` | Opening warehouse IN paired with opening quantity; zero opening has no movement | None | No inventory asset/equity journal; cost is catalog metadata, not a historical cost layer |
| Inbound / `adjustStock` increase | Warehouse IN with notes and deterministic key | None | No purchase/payables workflow or cost journal |
| Decrease / damage / correction | OUT for decrease/damage; existing `correction` means IN | None | No loss/gain journal; physical count approval module is absent |
| Warehouse -> rep / `confirmInventoryTransfer` | Equal warehouse OUT and custody IN | None | Ownership remains company; one atomic transfer, deterministic movement IDs |
| Rep -> warehouse | Equal custody OUT and warehouse IN | None | Same conservation rule; source balance checked |
| Rep -> rep | **Unsupported** | None | Do not invent a direct transfer or silently implement two unrelated postings |
| Invoice draft create/update/delete | None | None | Client draft operation; no finalized financial effects |
| Warehouse-sourced confirmed invoice | Tracked warehouse OUT | Customer +gross, -initial payment; actual company/rep cash per persisted creator role | Dr cash for initial paid portion; Dr customer for remainder; Cr sales for both portions |
| Representative confirmed invoice | Tracked own-custody OUT only; warehouse unchanged | Same receivable formula; rep-created initial cash belongs to rep cash | Representative cannot confirm warehouse/another rep source, even on an admin-created draft |
| Custom/untracked invoice lines | No inventory effect when legitimately untracked | Normal financial totals | Must not masquerade as tracked stock; existing positive inventory with disabled tracking now blocks posting |
| Zero-priced invoice line | Tracked quantities still leave stock | Zero line financial effect | Allowed alongside a positive invoice; an entirely zero-total invoice remains rejected |
| Invoice replay/shortage/failure | Replay creates nothing; failure commits nothing | Same | Atomic transaction; deterministic IDs and complete-posted flag guard |
| Confirmed invoice cancellation | **No general cancellation/reversal command** | No client rewrite permitted | Use supported sales returns where applicable; otherwise governed correction design required |
| JoFotara submission | Disabled retained callable fails without writes; not exported | None in supported disabled path | No assumption that government acceptance is inventory/financial posting |
| Cash receipt / `createReceipt` | None | Customer -amount; collector's actual cash +amount | Dr actual company/rep cash; Cr customer; allocation is oldest due/invoice date first |
| Bank/CliQ/check receipt | None | Customer -amount; no physical cash movement | Dr bank_unallocated / cliq_clearing / check_clearing; Cr customer |
| Receipt against opening receivable | None | Same; may be unallocated to invoices | Customer account still reconciles; no fabricated invoice attribution |
| Advances/overpayments | **New receipts exceeding positive receivable rejected** | Customer advances are not a supported new collection operation | Existing customer credit can arise through returns/opening balances; no silent conversion into cash/advance revenue |
| Receipt cancellation / `cancelReceipt` | None | Linked customer debit; original cash OUT inverse when safe; allocations restored | Immutable inverse financial pairs with linkage; admin-only; unsafe dependencies fail closed |
| Return against unpaid receivable / `confirmSalesReturn` | IN to the original tracked sale source | Customer -return gross | Dr sales; Cr customer; remaining receivable reduction tracked separately |
| Return of paid amount to customer credit | Same | Customer credit becomes more negative; cash unchanged | Dr sales; Cr customer |
| Cash-refunded return | Same | Customer -gross +actual refund; verified original collection account -refund | Dr sales/Cr customer, then Dr customer/Cr verified cash; caps against verified cash and prior refunds |
| Mixed/noncash collection refund | Source stock rules still apply | Cannot assume cash from clearing, or choose a convenient rep account | Cash refund blocks when source is absent, insufficient, or spans accounts; customer credit is supported |
| Free-item return | Original tracked source IN | Zero financial amount | No zero-valued journal; stock-only return supported, including draft validation |
| Return replay/over-return | No duplicate effect; sold quantity cap | No duplicate credit/refund | Confirmed history is reconstructed and checked against cached quantities/total; transaction conflicts serialize returns; precise rounding allocated cumulatively |
| Pending rep expense | None | No cash/financial effect until approval | Pending/rejected are excluded from finalized expense totals |
| Approved collected-cash expense | None | Rep cash -amount; customer unchanged | Dr expenses; Cr rep cash; no overdraft |
| Approved rep personal expense | None | Company/rep collected cash unchanged | Dr expenses; Cr representative payable; reimbursement remains unsupported |
| Admin expense | None | Company cash -amount | Dr expenses; Cr company cash; no owner-drawing classifier |
| Expense rejection | None | None | Only pending state may be rejected by client rules; posted expense reversal is absent |
| Rep cash settlement / `recordCashSettlement` | None | Equal rep OUT and company IN; combined cash unchanged | Dr company cash; Cr rep cash; linked source/destination movements; admin-only, balance checked |
| Other cash transfers / owner withdrawals | **No dedicated supported commands** | Cannot infer business expense vs equity movement | Classify only from reliable evidence and approved policy; do not relabel historical `other` expenses |
| Customer opening balance | None | Signed receivable/credit; no cash | Dr customer/Cr opening equity or opposite; unique original transaction |
| Opening-balance correction | None | Only signed difference affects receivable | Linked difference journal; original debit/credit retained, but original display metadata is currently amended |
| Company cash opening | None | Company cash IN once under existing designated-user/date control | Dr company cash; Cr opening equity; not used or changed in production by this audit |
| Customer reassignment | None | No financial rewrite | Current customer access changes; historic invoices/returns retain original representative; new collector cash follows actual collector |
| Product deactivation/soft deletion | Existing balances/movements retained | No financial effect | Future sale/transfer and returns of ineligible items block; no silent write-off |
| Quotation conversion | Draft creation only | None until trusted invoice confirmation | Original quotation keeps conversion linkage; no independent stock/cash posting |

### Payment method semantics

The supported receipt API values are `cash`, `bank`, `check`, and `cliq`.
`cash` means actual physical company/representative cash. Bank is unallocated
bank; check and CliQ remain their existing clearing accounts. Invoice
`paymentType`/`paymentMethod` values `cash`, `partial`, and `credit` describe
payment state; they are not card network classifications.

There is no explicit supported Visa/card collection or cheque-clearance,
dishonour, bank settlement, or CliQ-clearing settlement workflow in this
repository. Historical unknown methods must be reported for review, never mapped
to cash, bank, or card by guessing. No historical payments were reclassified.

## 3. Verified discrepancies and implemented corrections

All affected production scopes below are **unknown pending approved historical
inspection**. Local changes do not repair an existing discrepancy.

| ID / severity | Defect and potentially affected scope | Correction / evidence |
|---|---|---|
| F01 Critical | Tracking disabled while custody remains: confirmed sale skips OUT | Guard positive inventory behind untracked catalog; freeze catalog tracking/warehouse metadata. Red `tracking-before.log`, green final suite |
| F02 Critical | `if (!itemIds.add(itemId))` never detects duplicates in JavaScript. Transfer rows reuse movement/balance IDs; later row overwrites prior effect while document total includes both | Use `has` then `add`; reject before all effects. Red duplicate transfer regression |
| F03 Critical | `transaction.set` overwrites a pre-existing financial journal pair for an unposted business source | `transaction.create`; collision aborts stock, customer, cash, and source commit. Red test preserves sentinel original journal and balances |
| F04 Critical | Explicit foreign `item.companyId` accepted by invoice/transfer/return stock paths | Reject cross-company catalog stock while retaining existing legacy catalog compatibility. Invoice and transfer regressions failed before fix |
| F05 Critical | Mismatched custody identity accepted; missing balance with history can restart at zero on new delivery/return | Validate identity/quantity; missing-balance history query fails closed. Red identity and missing-custody regressions |
| F06 Critical | Invalid numeric cash/customer state silently coerced to zero | Strict persisted cash amount and `numberFrom` rejects malformed existing numeric fields. Cash regression failed before fix; malformed receivable test verifies atomic rejection |
| F07 High | Discounted unit price rounded first makes three split returns total 0.999 for a 0.998 sale | Allocate immutable net amount, tax, discount cumulatively, retaining rounding residuals. Frontend preview/drafts follow same allocation. Red 0.999 != 0.998 regression |
| F08 High | Free tracked line return fails when zero journal amount is built; draft layer also insists on positive money | Skip zero-valued financial pairs; allow nonnegative return draft total; physical return still posts. Red zero-journal regression |
| F09 Critical | Missing referenced invoice OUT movement treated as untracked, so return can silently omit IN | Missing/inconsistent source movement fails closed; new invoice line snapshots explicitly record tracking at posting. Red missing movement regression |
| F10 High | Retrying item creation after stock changed compares request against mutable current stock and rejects original key | Store immutable validated creation request for new items. Conservative legacy fallback retained; do not synthesize old request snapshots. Red creation replay regression |
| F11 High | Delayed item reporting event derives stock status/value/name from old event image | Re-read current item in a Firestore transaction; projection writes conflict with concurrent item changes. Red stale event `ok` vs `out` regression |
| F12 High | Binary midpoint error: 0.410 x 4.350 -> 1.783 rather than 1.784 | BigInt intermediates, three-decimal half-away-from-zero rounding, bounded numeric output; exact invoice product/tax/sums and return prorating; matching Flutter helper. Red decimal regression |
| F13 Critical risk | Fresh client keys on retry can duplicate receipt/expense/return/settlement/adjustment/item creation after a lost success response | Durable, actor/payload-scoped random key retained until authoritative readback succeeds. Four tests cover retry, restored preferences, concurrency, scope and canonical serialization |
| F15 Critical | Cached returned quantities can omit an earlier return; legacy rounding drift can be compounded by the next return | Reconstruct confirmed return quantities and line amounts before each post, compare cached quantities/total, and block unresolved historical residuals without changing history. Two red legacy/cache regressions in `legacy-return-before.log` |
| F14 Medium | Item metadata save submits stale stock/opening values or tries client stock correction denied by rules | Remove client inventory writes from metadata save; lock existing stock/opening/tracking/warehouse controls. Four responsive bilingual regression cases; ordinary price edits remain available |

Return authorization test fixtures originally contained stock movement stubs
without direction/reference/quantity. They were updated to model actual posted
movements; authentication/access assertions remain. They are not examples of
production records being automatically repaired. Incomplete historical source
movements now require investigation rather than being treated as permission to
create stock.

### Modified source areas

- Trusted backend: `common.ts`, new `exact_decimal.ts` and `custody.ts`,
  `cash_ledger.ts`, `confirm_invoice.ts`, `confirm_inventory_transfer.ts`,
  `confirm_sales_return.ts`, `inventory.ts`, `financial_ledger.ts`,
  `financial_ledger_mappings.ts`, and `operational_search_projection.ts`.
- Security: `firestore.rules` catalog metadata restrictions and nonnegative
  return draft amounts. Existing server-owned balance/journal restrictions remain.
- Flutter: new `exact_decimal.dart` and `pending_posting_keys.dart`; invoice
  totals, financial payment calculator, receipt/expense/return/settlement/item/
  adjustment repositories, return form allocation, item form/edit screen,
  and English/Arabic item guidance.
- Verification: new `inventory_financial_integrity.test.js`,
  `integrity_reconciliation.test.js`, `exact_decimal_test.dart`,
  `pending_posting_keys_test.dart`; expanded rules and item layout cases;
  valid movement provenance in existing return fixtures.
- Tools: offline `integrity_reconciliation.js`, loopback-only
  `run_integrity_tests.js`, and package scripts `test:integrity`/`audit:integrity`.
  No new Firestore index was required for the added equality-only history query.
  Production/staging index availability itself was not checked.

## 4. Independent reconciliation

### Checker contract

`functions/scripts/integrity_reconciliation.js` imports no Firebase SDK and has
no credentials, online reads, apply option, or database write path. It accepts
JSON collections and computes thousandth-unit sums independently of posting
helpers. Missing collections, incomplete history attestation, legacy tracking
ambiguity, unrecognized methods/movements, and unresolved classifications are
visible warnings; they prevent a PASS. Invalid values and discrepancies produce
affected document paths, expected/actual/difference, and an approval-required
repair note. Evidence is never mutated.

The input has `companyId`, `fullHistory`, `collections`, and optional
`reportTotals`. Every collection listed in exported `COLLECTIONS` must be present,
including empty ones. Each row includes the real document ID as `id`. Attesting
`fullHistory: true` requires a complete export through a defined cutoff with all
approved opening events; the flag is not proof by itself.

It checks:

- Each movement's before +/- quantity/amount = after and duplicate IDs.
- Warehouse balances by item and warehouse, custody by representative/item,
  and cash accounts against complete movement sums.
- Invoice expected tracked quantities against actual source-specific OUT rows,
  including linked movement existence and unposted invoices with effects.
- Confirmed transfer quantities, unique lines, equal/opposite warehouse and
  representative effects, and source ownership.
- Company-owned inventory against external opening/adjustment events minus
  tracked sales plus eligible tracked returns; internal transfers net to zero.
- Return quantity/amount caps and full-return financial total against immutable
  source line totals; tracked return IN quantities.
- Customer balances independently from gross sales minus initial collection,
  active receipts, return credits/refunds, and original opening debit/credit
  plus adjustments; then against the customer ledger and financial ledger AR.
- Actual cash from initial collections, cash receipts, eligible refunds,
  posted expenses, linked settlements and explicit opening cash; then against
  movements, balances and general ledger cash accounts.
- Equal-sided journal pair validity, economically wrong cash/AR account pairs,
  independent sales/receipt/return/expense/settlement metrics, and supplied
  report/export totals. Pair equality alone cannot prove economic correctness.

Limitations: it does not certify bank clearing, taxes, cost layers, GL account
activity projection completeness, legal chart mappings, chronological stock
availability over an imported history, every legacy cancellation dependency, or
every arbitrary malformed schema. A snapshot at inconsistent read times can
produce discrepancies; use an approved consistent export/cutoff. The schema is
the original app's single warehouse balance per item, not arbitrary multi-site
inventory. Unknown records stay unresolved.

### Synthetic lifecycle result

Artifacts are in `output/integrity-audit/` and are explicitly synthetic.
The transaction fixture exercises opening stock/inbound, delivery, representative
partial sale, collection, credit return, stock return to warehouse, personal and
collected-cash expense approvals, settlement, company expense, customer opening,
and bank receipt cancellation. Ledger projections are replayed twice per entry
before summary comparison.

| Independent result | Expected / persisted |
|---|---|
| Main item: warehouse opening 20 - delivery 8 + returned custody 2 | 14 warehouse |
| Main item custody: delivery 8 - sale 3 + sales return 1 - warehouse return 2 | 4 custody |
| Main item company-owned: 20 - external sale 3 + eligible return 1 | 18 total |
| Separate opening/inbound replay item: opening 5 + inbound 2 | 7 warehouse |
| Company cash: settlement 20 - company expense 3 | 17 |
| Rep cash: initial payment 10 + receipt 20 - approved cash expense 2 - settlement 20 | 8 |
| Customer: sale 30 - initial cash 10 - receipt 20 - return credit 10 | -10 customer credit |
| Opening customer: opening 10 - bank receipt 10 + receipt cancellation 10 | 10 receivable |
| Report net sales / receipts / returns / expenses / settlements | 20 / 20 / 10 / 6 / 20 |
| Comparisons / discrepancies / warnings | **51 / 0 / 0** |

The snapshot contains 2 items, 1 invoice, 2 inventory transfers, 1 sales return,
5 warehouse movements, 4 custody movements, 1 custody balance, 2 customers,
7 customer transactions, 2 receipts, 3 expenses, 1 settlement, 6 cash movements,
2 cash balances, and 11 financial ledger pairs. The 11 offline checker tests
also deliberately corrupt records to prove detection of missing deductions,
wrong custody, duplicate identities, unpaired cash settlement, balanced journals
on wrong cash accounts, phantom receivables, report errors, and invalid precision.

**Real historical reconciliation result: NOT RUN / BLOCKED.** No real zero
discrepancy result, affected-record count, or live financial balance is claimed.

## 5. Verification and reproducibility

| Run | Exact result |
|---|---|
| Original backend baseline | 190 passed, 0 failed, 0 skipped |
| Original Flutter baseline | 411 passed |
| Initial new integrity regressions, before fixes | 14 tests: 3 passed, **11 failed** |
| Tracking bypass regression before guard | 1 failed as expected |
| Catalog policy restriction before rules fix | 1 failed as expected |
| Decimal midpoint before arithmetic fix | 1 failed as expected |
| Missing custody balance before history guard | 1 failed as expected |
| Legacy return drift and incomplete quantity cache before history reconstruction | 2 failed as expected |
| Final complete backend suite | **223 passed, 0 failed, 0 cancelled, 0 skipped** |
| Final complete Flutter suite | **423 passed** |
| Final static analysis | TypeScript compilation passed; Flutter no issues |
| Final release web build | Passed, `FATOORA_ENV=test`, no deployment |
| Whitespace validation | `git diff --check` passed |

Backend total = 190 existing + 22 transaction/precision integrity cases +
11 independent reconciliation cases. Flutter total = 411 existing + 4 decimal +
4 pending-key + 4 locked item form locale/size cases. Total final test count:
**646**. Bilingual form cases use English/Arabic and 320/1366px; existing tests
also exercise tablets, enlarged text, invoice/return/financial screens, PDFs,
Excel workbooks, permissions, pagination and stale responses.

The final backend runner resets **only named synthetic projects on a loopback
emulator**. An intermediate run without reset found leftover fixture records;
its failures were not accepted as product regressions. The reproducible runner
now isolates each whole run. A later clean run exposed four provenance-stub
fixture failures and a legacy checker inference problem; these were corrected
without weakening the production source guard. Only the final passing results
above are the acceptance evidence for the changed paths.

The installed Firebase CLI required Java 21 and attempted an unavailable emulator
download. Tests used Android Studio's JBR 21 and the already-cached Firestore
emulator v1.19.8 bound to `127.0.0.1:8080`. No live Firebase endpoint was used by
tests. Local SDK cache access required sandbox escalation for Flutter commands.

Example local verification commands (no deployment):

```powershell
# Start a dedicated Firestore emulator; cached-runtime fallback used in this audit:
& 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe' -jar `
  "$env:USERPROFILE\.cache\firebase\emulators\cloud-firestore-emulator-v1.19.8.jar" `
  --host 127.0.0.1 --port 8080 --rules firestore.rules

# In a separate terminal:
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
npm.cmd --prefix functions run test:integrity
flutter.bat test --no-pub --reporter expanded
flutter.bat analyze --no-pub
flutter.bat build web --release --no-pub --dart-define=FATOORA_ENV=test

# Offline evidence check; no Firebase access, exits 0=PASS, 1=FAIL, 2=BLOCKED:
node functions/scripts/integrity_reconciliation.js `
  output/integrity-audit/synthetic-lifecycle-snapshot.json
```

Backend tests call transaction functions and wrapped callables directly; rules
tests use authenticated SDK test contexts. Real JWT restoration, callable HTTP
transport, deployed indexes, Android/device builds, multi-device offline recovery,
and production trigger delivery were **not** exercised end to end.

## 6. Coverage gaps and residual financial risks

| Risk | Assessment / required gate |
|---|---|
| Historical Jihad incident and other affected data | Critical, BLOCKED by approval review. Manual historical reconciliation is required; no production repair may be inferred from fixture results |
| Existing disabled tracking or wrong balances | New guards prevent further unexplained posting; they do not reconstruct or alter old state. Such records may now be operationally blocked |
| Closed periods/backdating/future dates | No accounting period subsystem. Business dates can be backdated within current workflows; migration must define approved posting policy first |
| Incomplete accounting classification | Gross sale amounts go to sales, including tax; no separate discount/tax liability/inventory asset/COGS postings. Balanced pairs do not establish complete accounts or profit |
| Costs and valuation | `inventoryValue` is current catalog stock x current catalog cost, with asynchronous reporting updates; it is not a reconciled historical inventory asset valuation. No reliable issue-cost provenance was invented |
| Audit atomicity | Audit/search/report triggers are asynchronous. Operational effects/journal pairs commit together, but audit event delivery is not in the same transaction/outbox |
| Opening balance immutability | Existing correction mechanism keeps original debit/credit and adds the difference, but changes original amount/signed/display metadata. Reconstruct with debit/credit; staged immutable source design required |
| Unsupported inventory operations | Rep-to-rep, custody physical-count adjustments, independent multiple warehouses/locations, governed product tracking conversion, and stock-count approval are absent |
| Unsupported financial operations | Advance receipts/overpayments, explicit Visa, bank/check/CliQ settlement/dishonour, expense reimbursement, owner drawings and generic posted-event reversals are absent |
| Owner/personal classification | `other` expense may contain personal withdrawals; reliable transaction purpose/equity ownership is missing. Accountant review required; no automatic keyword-based reclassification |
| Deactivated/deleted source products | Historical snapshots retained, but eligible return posting blocks. A governed physical-return exception policy is still needed |
| Historical incomplete movement snapshots | Returns now fail closed when referenced OUT provenance is missing/inconsistent. Resolving a genuine old return requires source evidence and approved correction workflow |
| Retry intent beyond identical payload | Persisted keys cover unchanged actor/request, including failed readback. Changed notes/date/amount are a different fingerprint; multi-device intent identity and restoration of abandoned forms are not guaranteed |
| Invoice creation response loss | Draft creation can still leave a saved draft when response/ID is lost; draft retry can create another draft. No financial effect until confirmation. A durable draft intent/workflow would close this remaining lifecycle gap |
| Reports and exports | Independent full-scope synthetic summary reconciles. Filtered reports, historical legacy aliases, exact date-boundary projections and all live export rows are not independently certified |
| Company-owned totals in UI | Inventory dashboard aggregates active tracked `items.currentStock`; custody is separate and deactivated/deleted stock is filtered. Its number is not complete company-owned stock; use the independent combined reconciliation |
| Projection readiness | Custody `hasStock` and item reporting are asynchronous; current-item reporting stale-event defect fixed. No universal freshness watermark/discrepancy banner exists on every screen |
| Large transactions | Invoice/transfer line limits are bounded. Receipt allocation can span >250 invoices, while safe cancellation caps allocations at 100. Very large postings/cancellations need explicit transaction-budget and governed alternative handling |
| Legacy/global catalog | Explicit foreign company IDs now reject. Catalog records without company IDs retain original legacy compatibility; multi-company segregation requires a separate reconciled ownership migration |
| Numeric schema | Exact intermediates improve verified posting paths; numeric storage remains three-decimal doubles. Unknown legacy precision/currencies and extreme-value report aggregation require policy and import review |

## 7. Historical affected-record and correction protocol

The offline checker emits exact affected paths once authorized evidence is
supplied. Until then, the real affected-record list is **unknown**, not empty.
No executable production correction or apply script is provided.

For each proposed correction, the approval package must include project/company,
original source and movement IDs, stable export hash/cutoff, actual physical
source/destination, expected vs observed quantity/money, downstream dependencies,
cost evidence if applicable, signed correction components, resulting invariants,
and a unique correction/reversal identity.

| Verified historical condition | Candidate compensation, only after evidence/approval |
|---|---|
| Real custody sale with missing OUT | Linked custody OUT for proven unposted delivered quantity; no duplicate sales/receivable/cash posting |
| Wrong warehouse source actually deducted | Linked warehouse IN and custody OUT for proven misattributed delivery; preserve original invoice/ownership and financial records |
| Duplicate-row transfer under-posted | Compare actual delivered/returned quantity with full movement history. Post only the proven difference with paired locations; do not assume the document total equals physical delivery |
| Return rounding over/under-credit | Linked customer financial correction for proven residual, and actual refund correction only if cash evidence supports it; no invented cash |
| Missing/malformed balance projection | Reconstruct complete authoritative history including approved opening; review unresolved sources before any separately approved projection rebuild |
| Overwritten journal history | Recover original evidence from an approved backup/export; propose linked corrections in a new book/version. Do not overwrite current history to simulate restoration |

Approval is required for every historical correction. Apply a maintenance lock or
approved posting pause at the affected scope, compare-and-set against reviewed
source versions, post bounded compensations once, and run independent before/
after reconciliation. Rollback uses inverse compensations or a versioned report
cutback; it never deletes posted events or rewrites original journals. The
present app does not expose all required governed stock/correction commands;
their absence is a deployment blocker, not permission to edit balance documents.

## 8. Modernization strategy

**Updated 2026-11-03, Asia/Amman:** the owner's approved direction is to rebuild
financial architecture around proper double-entry accounting, then replace the
Firestore business dataset through validated historical Excel import. Permanent
legacy-schema compatibility is no longer an architectural constraint.

The canonical [financial modernization strategy](../financial-modernization-strategy.md)
and [Excel migration specification](../excel-migration-specification.md) replace
the previous Phase A-F future plan in this section. They cover retained workflow
behavior, a new accounting domain/book, exact arithmetic, physical inventory,
opening/history boundaries, economic-event deduplication, independent financial
and inventory reconciliation, isolated rehearsal and protected reset scope.
The owner has since fixed Firestore, Firebase Authentication and Cloud Functions
as the platform. The [Phase 2A design](../phase2a-firestore-accounting-architecture.md)
defines the Firebase-only target and proposed bounded Phase 2B batch. Company
accounting policies still require review; reference-platform approvals do not
transfer here. Neither design phase implements an engine or authorizes production work.

The [2026-11-04 owner refinement](../phase2a-inventory-cash-integration.md)
removes purchase-cost/COGS prerequisites for physical stock/sales, defines
informational reference-selling estimates and a detailed reconciled cash ledger,
and requires integration into existing functions/models/repositories/screens.
Historical cost gaps in sections 1-7 are not gates on this quantity-only scope;
they still cannot be filled from selling prices or used to assert profit.

Sections 1-7 retain the historical findings, local fixes and recorded validation
limits. Their synthetic results do not certify production history or prove Excel
completeness. The Jihad investigation remains unresolved; Phase 1 does not repeat
the rejected production lookup or authorize an in-place historical repair.
Section 7's correction protocol applies only to a separately approved correction;
the new strategy also permits replacing legacy structures after validated
reconstruction and separately approved cutover.

## Required next action

Review Phase 2A policy decisions/Phase 2B scope and assemble source coverage, identity,
opening-balance and independent-control evidence required by the specification.
Do not implement later phases or treat missing historical data as zero. Before
any eventual reset, back up Firestore and required application configuration and
prove restoration in isolation. No production deletion, deployment, destructive
operation or Firebase Authentication reset is authorized by this strategy update.
