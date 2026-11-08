# Reassignment and return attribution: staging release candidate

Prepared 2026-11-08 for **`fatoora-original-staging` / `5438538531` only**.
**PASS: local candidate verification. BLOCKED: deployment/promotion until the
staging gates below pass.** No deployment, production access or historical
financial corrections were performed. Accounting remains at Phase 2B-5.

## Reviewed result and exact scope

| Component | Candidate scope |
| --- | --- |
| Firestore indexes | **32 additions**, all `invoices`, `COLLECTION` scope. Retain all 268 existing indexes and all field overrides: desired total 300. No deletion. |
| Firestore Rules | Borrowed invoice history requires current customer assignment and trusted `financialPosted == true`. Company/user approval checks and mutation ownership remain intact. |
| Cloud Functions | **`confirmSalesReturn` only**, Node 22, `us-central1`, codebase `fatoora-original-staging`. Preserve existing transport IAM and captured runtime/build identities. |
| Hosting | Existing `fatoora-original-staging` site, frozen Web artifact. |
| Android | Existing `com.fujika.fatoora.original.staging` package, **debug signature only**, for acceptance distribution. |
| Excluded | Production and V1, IAM changes, Auth/database reconfiguration, function creation/deletion, migrations, seed/reset scripts, historical ledger rebuilds and accounting implementation. |

The frozen scope is [reassignment-release.review.json](../config/firebase/reassignment-release.review.json).
The original staging provisioning wrappers intentionally pin the old Rules,
indexes and Functions source. **Do not reuse or relax those wrappers for this
release.** They would either reject the change or prepare the original archive.
The candidate has its own deployment configuration without those predeploy hooks.
The preparation/verification tools have no deploy action and retain `deployAllowed: false`.

Source comparison against the retained deployed Functions archive found only
three changed source modules: return posting, its shared ledger mapper and the
guarded offline rebuild mapper. AST comparison confirms the only changed shared
mapping function is `buildSalesReturnFinancialLedgerEntries`. All **35 callable/
event endpoint definitions**, package lock, runtime adapter and other posting
mappings match the deployed source. The rebuild is passive source, never executed.
No Phase 2B-5 settlement/preflight/journal-intent source changed.

The existing staging foundation changes in the working tree were also reviewed:
pinned native/Dart registrations, debug-only flavor, SDK guards, ignore entries
and original provisioning/acceptance tooling. They remain separate from this
release's one-service deployment scope. Production default files and aliases are
unchanged; never use a default-project deployment command.

## Index review and additional correction

The original 64-index proposal had no exact duplicates, but was not minimal.
Read-only **native staging Query Explain** (`analyze: false`) proved all 42 tested
owner-query shapes work with the existing indexes, including eight sorts, both
directions, search, date ranges and combined filters. Their 32 proposed indexes
were removed from the candidate. This follows Firestore's documented
[index merging](https://firebase.google.com/docs/firestore/query-data/index-overview#use_index_merging).

Review also found a missed lifecycle case: financially posted electronic invoices
can become `pendingSubmit`, `accepted` or `rejected`. The former confirmed-only
history condition hid them. Rules, repository queries and detail checks now use
the trusted posting flag. Drafts remain unposted and protected. Existing return
eligibility, including confirmed-only return actions, is unchanged.

The 32 remaining indexes cover the posted-history branch:

`[searchKeywords CONTAINS,] customerId ASC, financialPosted ASC, <sort> ASC|DESC`

There are eight existing sort fields × two directions × search/no-search. Each
query orders document ID in the same direction as its final sort, matching the
implicit index suffix. No lifecycle-status equality is assumed. Explicit status,
type, payment and return filters still reach the existing query builder.

Live metadata verified **268 READY indexes and 35 ACTIVE Functions**. The 42 tested
new history-query shapes currently report **no matching index**, as expected
before these additions are deployed. There were no other planner failures. This
is a release dependency, not an emulator-proven readiness claim. Native planning
must pass after index creation and before publishing Rules/client changes.

## Accounting and permission evidence

- Real emulator Auth tokens, callable HTTP, client Rules and event triggers
  exercised transfer, historical invoice/statement reads, old-rep revocation,
  stale drafts, new sales, historical-debt collection, partial cash refund,
  idempotency, cash/custody ownership and cross-company/anonymous/inactive denial.
- Returns reduce company and original-seller sales once. Refund ledger cash
  activity follows the actual collecting account and contributes zero sales.
  Assignment does not alter invoices, receipts, returns or balances.
- Electronic lifecycle history reads pass; mutation and return permission checks
  remain independent. Other representatives' drafts remain unreadable.
- Company reconciliation includes Admin and inactive sellers without changing
  their original invoice ownership. The current UI's active-rep table is a
  **subset**, not the complete company reconciliation.

One HTTP acceptance fixture produced:

| Metric | Amount |
| --- | ---: |
| Gross billed invoices, including tax, before returns | 203.000 |
| Returns, including tax, on actual return date | 14.500 |
| Operational net billed sales, including tax | **188.500** |
| Seller reconciliation | **58.000 Admin + 116.000 active rep + 14.500 inactive rep** |
| Net tax after returns | 26.000 |
| Net sales excluding tax | 162.500 |
| Initial invoice collections | 68.000 |
| Receipt collections | 0.000 |
| Receivables | 120.500 |

`getDashboardSnapshot.totalSales` remains return-adjusted **tax-inclusive billed
sales**. It is not tax-exclusive revenue or cash collected. Cash/credit/partial
buckets classify original invoice payment terms; later receipts do not create
sales. Invoice/return tax fields remain separate. Customer statements reconcile
debits and credits, including refunds, to customer balances. Portfolio/dashboard
receivables retain existing active-customer/positive-balance filters; these are
not automatically the full historical ledger control balance. Existing UI labels
and screens were preserved; this documented metric contract must also be used in
acceptance and must not be treated as a completed tax/COGS general ledger.

## Verification

| Check | Result |
| --- | --- |
| Full backend regression suite | PASS — **683** |
| Full Flutter regression suite | PASS — **573** |
| Auth/HTTP/Rules/triggers accounting acceptance | PASS — **2** complete scenarios |
| Existing staging guards/runtime serializer | PASS — **5** |
| New release scope/index/no-deploy guards | PASS — **4** |
| TypeScript build/lint and full Flutter analysis | PASS |
| Web and Android debug builds | PASS |
| Effective native SDK pairing, APK package/label/signature and compiled Web SDK inputs | PASS |
| Native pre-release query review | PASS for 42 owner shapes; BLOCKED for 42 history shapes pending indexes |
| Live candidate deployment and interactive Web/Android staging acceptance | **NOT RUN — explicit release hold** |

Data-writing tests used isolated Auth/Firestore/Functions emulators, demo project
`demo-fatoora-release-test` and synthetic data. Existing backend test namespaces
also remained on loopback. The Functions emulator used deliberately invalid
synthetic cloud credentials; no real ADC was supplied to the emulated services.
Live staging requests were limited to resource metadata and non-executing query
plans. No live financial document was read or written.

## Artifacts and rollback

Candidate directory: `build/reassignment-release/rc1/`.

- `functions/`, `web/`, `android/app-staging-debug.apk`, Rules, complete index
  manifest, staging-only `firebase.json`, scope and input hashes.
- `rollback/functions.zip`: original runtime-compatible deployed source archive,
  SHA-256 `6e38f98661aee08998d26c4b745d5ee3a1060c35ef164433d6ecbeed47f8b3ad`.
  Live source object generations match the retained archive evidence.
- `rollback/firestore.rules`, previous index manifest, previous debug APK and
  previous Web files. Local Web files match the pinned Hosting version's gzip-9
  hashes; Firebase-generated bootstrap files remain in the immutable version.
- `rollback/live-baseline.json` pins the original Hosting release/version,
  ruleset, function source generations and service identities.
- `evidence/` contains tests, native plans, per-index decisions, accounting
  reconciliation, dependencies, artifact pairing and complete working-tree review.
- `SHA256SUMS.json` seals the candidate. Verify with
  `node scripts/reassignment-release-candidate.cjs verify` before any future use.

Retain additive indexes on rollback. Restore the pinned Hosting version/debug
client, old Rules and, if necessary, the original `confirmSalesReturn` source with
the same identities. Hold staging posting activity while rolling back; the old
refund implementation can reproduce the attribution bug. Preserve all newly
posted immutable records and audit trails. Never restore database snapshots,
rebuild journals, reset balances, delete receipts/returns or rewrite seller IDs.

## Future staging-only execution and acceptance gates

Execution still requires a later instruction; this document is not authorization.
An approved executor must verify frozen hashes and fresh live baseline, use the
existing staging-only keyless deployer and builder, and preserve transport IAM.

1. Keep staging write clients out of use during rollout. Check there is no drift
   from the recorded Rules, source generations, existing indexes or Hosting version.
2. Add only the 32 indexes using the frozen complete manifest. Refuse deletions,
   forced prompts or unrelated new indexes. Wait until all 300 indexes are READY.
3. Run `node scripts/reassignment-release-live-read.cjs --require-ready`.
   Its native matrix must have zero missing indexes/other failures. If not, stop
   before publishing Rules or clients; no speculative index deletion is permitted.
4. Deploy only `functions:fatoora-original-staging:confirmSalesReturn` from the
   frozen candidate; preserve Node 22, region, runtime/build identities and invoker
   settings. Verify ACTIVE state, uploaded archive and unchanged other services.
5. Publish the frozen Firestore Rules, then Hosting to the existing staging site.
   Use explicit project `fatoora-original-staging` and the candidate configuration
   for every step. Distribute only the pinned staging debug APK for acceptance.
6. In a newly authorized synthetic acceptance company, verify Admin/A/B/inactive
   and foreign/anonymous roles: old and electronic invoice history, statement
   pagination and revocation, stale drafts, new sales, partial/full returns,
   credit and cash refunds, mixed-account rejection, collections/cancellation,
   original custody and seller ownership, and asynchronous projection convergence.
   Use fixed expected totals and reconcile all seller categories, tax, collections,
   receivables and cash. Existing historical companies/records are out of scope.
7. Exercise the existing Web screens and staging Android app interactively,
   including customer filtering/search/sorts, invoice PDFs and statement exports.
   Check disabled actions and denied reads. Confirm no duplicate UI/workflow.
8. Record PASS receipts and artifact hashes. Only after explicit staging acceptance
   may accounting work resume from **Phase 2B-5**; this release enables no new
   double-entry postings, tax-liability or inventory/COGS mappings.

Any financial mismatch, permission leak, stale client artifact, unexpected resource
change or failed native query is a stop criterion. Missing legacy identities and
existing historical cross-collector refund ledger discrepancies require separate
review; no correction is part of this release.
