# Jihad investigation: bounded release plan

Review only. No production requests, writes, corrections or deployments were
performed while preparing this plan. Detailed operational IDs and amounts
remain in the existing private evidence and the investigation response, outside
Git. No production documents are copied here.

## Evidence and decision

Existing run `5fcb126df34d30fb1713f5da`, snapshot
`2026-11-02T13:13:59.804871Z`: 54 confirmed invoices, 180 custody movements,
20 custody balances, 22 transfers, 3 returns. Of 1,224 comparisons, 1,223 pass;
the sole failed numeric comparison is return allocation. Visibility metadata is
a separate nonnumeric finding. No financial analysis completed: the existing
customer-coverage gate stopped the run.

Custody OUT comparisons exist for 53 invoices, and all match. All 20 source,
movement and persisted quantity closings match. The remaining invoice has no
item-level custody comparison; the derived report does not retain its line
types, item references and quantities, so its zero-deduction expectation cannot
be independently established from that report. Do not label it a missing
deduction or certify all 54 invoices without those already-existing source
details.

The flagged visibility item has the correct zero quantity. Its `hasStock`
expectation is false. The report records the mismatch but omits the actual flag
value/type, so true, missing, null and malformed values cannot be distinguished.
It also lacks projection timestamps/trigger outcome and deployed revision.

## Local fixes and limits

* F07: `confirm_sales_return.ts` allocates immutable net/tax/discount components
  cumulatively, using `exact_decimal.ts` integer prorating. This fixes future
  allocation rather than reusing a rounded per-unit price.
* F12: shared exact decimal arithmetic supports product, tax and sum precision.
* F15: the return handler reconstructs confirmed history, compares quantities
  and totals with cached data, and rejects historical allocation residuals with
  `data-loss`. It does not silently compensate earlier returns.
* F01/F09 and custody identity/opening guards are present locally. Existing
  evidence does not demonstrate their missing-deduction symptoms in the 53
  invoices with custody comparisons.
* The custody search projector already re-reads the latest document
  transactionally in HEAD and the working tree. The new F11 local diff fixes
  item reporting, which is a different projection. Do not attribute the custody
  flag finding to F11 or assume redeploying that function repairs history.
* Authoritative invoice/return/transfer writers still leave `hasStock` to an
  asynchronous projector. One inconsistent snapshot proves neither persistent
  trigger failure nor a particular deployed code defect. No new custody
  projection patch is established by the saved evidence.

Historical return amounts remain unresolved. Financial ledger/cash effects,
the full customer-coverage gap and actual disbursement cannot be determined
from the saved comparisons. Local fixes do not repair those records.

## Smallest candidate release, after separate approval

1. Isolate a reviewed release checkout. Pin its source hash and the prior
   approved artifact/revision from existing release records. If the prior
   artifact or dependency diff is unknown, keep release BLOCKED. Do not deploy
   the entire dirty working tree.
2. Scope the first release to `confirmSalesReturn` in `us-central1`. Review its
   complete imported dependency changes, including exact decimal/common
   arithmetic, custody guards, journal create-preconditions, and return mapping.
   These changes travel with this one function; selective deployment is not a
   substitute for dependency review. Preserve existing auth/invoker/IAM policy.
3. Do not include hosting, Flutter, rules, indexes, migrations, financial
   rebuilds, item-reporting functions or a custody projector redeploy. Review a
   matching frontend preview release separately if needed; the server remains
   authoritative. No historical record is replayed as a release test.
4. Run the focused gates below against the exact release artifact. Review the
   known effect that further returns on inconsistent historical invoices will
   stop for reconciliation. Do not remove that guard to make history pass.
5. Only after release approval, the intended selector would be:

   ```powershell
   firebase deploy --project fatoora-6b192 --only functions:confirmSalesReturn
   ```

   This command has **not** been executed. This plan grants no production
   changes or additional monitoring/data access. Any later observation uses a
   separately authorized scope; no synthetic production invoice is created.

## Focused gates and existing evidence

Reuse `output/integrity-audit/node-final.log`: the existing split-return,
historical-rounding rejection, incomplete return-cache rejection,
sale/replay custody deduction and idempotent search-projection tests passed.
The later read-only auditor's focused suite also passed 49 tests. Those are
synthetic results, not evidence of deployed versions or corrected history.
No full audit was repeated for this investigation.

For a release artifact, build/typecheck and rerun only these existing backend
regressions on a dedicated loopback Firestore emulator:

```powershell
Set-Location C:\src\fatoora\functions
npm.cmd run build
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
node --test --test-concurrency=1 --test-name-pattern='split returns allocate|legacy return rounding|incomplete returned-quantity|representative sale deducts|search projection repairs' test/inventory_financial_integrity.test.js test/search_inventory.test.js
```

The checks must preserve total original return allocation, reject inconsistent
history without side effects, preserve exactly-once custody deduction, and
change only metadata when reconciling a projection. Use existing synthetic
fixtures; never substitute production IDs or data. Before release, add a generic
synthetic test of the specific split-ratio pattern and verify that its residual
is preserved, without copying private transaction data into Git. A release
artifact is not approved merely because earlier working-tree tests passed.

## Rollback

Keep the prior function artifact and a reviewed safe forward patch. On a
regression, suspend return posting through the existing operational process;
restore only the reviewed function artifact if it preserves the necessary
integrity guards. If the prior version reintroduces premature price rounding or
allows inconsistent history, keep returns suspended and roll forward instead.
Never undo persisted transactions, delete journals, edit balances, or replay
invoices as rollback. Any financial correction is a separate evidence and
approval process.

Projection release remains BLOCKED pending the actual flag/type, timing and
trigger/deployment evidence. An old metadata row may need a separately approved
metadata-only repair after verification; function deployment alone does not
backfill it. No quantity repair is indicated by the saved numeric comparisons.
