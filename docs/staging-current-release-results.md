# Current Fatoora staging release

2026-11-08, Asia/Amman. **fatoora-original-staging / 5438538531 only**.

**Deployment PASS. Security, compatibility, integrity and real API/financial
acceptance PASS. Visual browser acceptance BLOCKED by automation policy.**

The current working tree was released. RC1 archive recovery was not resumed.

| Component | Final deployed state |
| --- | --- |
| Firestore indexes | **300 READY**, 32 additions, zero removals; all 268 original indexes and field configurations retained. All **84 native query plans PASS**. |
| Firestore Rules | **a96acaef-4431-4f95-9af6-08fb9ea67625** |
| Cloud Functions | **35/35 ACTIVE** on new revisions; Node 22, unchanged Firebase Admin **12.7.0** and Functions SDK **5.1.1**; Functions Framework **3.5.1**, explicitly locked. |
| Flutter Web Hosting | Version **9c820eb4da13e96b**, release **1794140590220000**; **41 published assets** match the sealed artifact. |
| Configuration repair | Added only the missing `documentSettings` map, using the existing Flutter model defaults; no original setting value changed. |

Live site: [fatoora-original-staging.web.app](https://fatoora-original-staging.web.app/).
Deployment followed indexes/readiness → Rules → compatible Functions → Web.
Exactly one new Hosting release was published. No Android build or distribution,
IAM changes, production access or accounting implementation was performed.

Exact revisions, build IDs, source generations, checksums and unchanged invocation
permissions for every Function are in
[backend-deployment-verification.json](../.staging/fatoora-original-staging/current-release/evidence/backend-deployment-verification.json).
The deployed source archive SHA-256 is
`2faa245e1544384652a31be142353ca37b91d4d2dc621aee126c705348026f97`.

## Dependency remediation and compatibility

All **17 original affected-package findings** are resolved: one critical, five
high and eleven moderate. Clean production installation and audit report **zero
findings**. Inspection of the exact **35 built container images** also reports
**zero advisory packages**, with no separately injected framework remaining.

Smallest patched versions were pinned through explicit overrides:
`@fastify/busboy 3.2.2`, `@grpc/grpc-js 1.14.5`, `body-parser 1.20.9`,
`fast-xml-parser 5.10.1`, `node-forge 1.4.1`, `protobufjs 7.6.5`,
`proxy-addr 2.0.8`, `qs 6.16.1`, and `uuid 11.1.1`.
No Firebase SDK major upgrade or `npm audit fix --force` was used.

Actual image inspection found that the original managed framework had its own
older HTTP parser and additional vulnerable transitive packages. Pinning the
already deployed framework version inside the application lockfile applies the
patches to that request path too. This required updating **all 35 existing
Functions**, rather than leaving 34 with vulnerable dependencies. Their business
code, endpoint contracts, runtime/build identities, triggers, service settings
and invocation permissions remain unchanged apart from the reviewed return fix
and shared dependency patches.

The critical proxy advisory depends on particular proxy-trust configuration; an
application IP-based authorization bypass was not established. The old framework
parser was on the pre-authentication HTTP path. Malformed-compression regression
testing ran on loopback, without attacking staging. UUID CommonJS/v4 compatibility
was verified at all existing SDK consumers.

## Verification

| Check | Result |
| --- | --- |
| TypeScript build; clean production install/tree/audit | PASS |
| Dependency-impacted backend regressions | **686 PASS**, zero failures/skips |
| Emulator Auth → callable HTTP → Rules → posting/triggers | **2 PASS** |
| Original/current Rules with incomplete staging settings | **2 PASS** |
| Current deployment target/permission guards | **3 PASS** |
| Unaffected Flutter tests and static analysis | Reused **573 PASS**, clean analysis; source hashes verified unchanged |
| Unaffected staging runtime/provisioning checks | Reused **5 PASS** |
| Direct pinned framework authentication/reporting | PASS |
| Real staging acceptance | **4 scenarios PASS** |
| Published assets, Firebase project configuration, SPA routes, alias and CORS | PASS |
| Post-publication password login, reporting, anonymous/cross-company denial | PASS |

Real staging covered reassignment, original-seller history and totals, customer/
statement access revocation, denied stale drafts, historical-debt collection,
partial returns, representative/company cash refunds, receipt cancellation and
idempotency, inactive-user denial, inventory adjustment/transfer, and a return
after transfer back into the original seller's custody. Warehouse quantity was
20 and original custody 8; the new owner received zero sales from that return.

The final synthetic all-seller company reconciles as follows:

| Measure | Amount |
| --- | ---: |
| Gross billed invoices, including tax | 203.000 |
| Returns, including tax | 72.500 |
| Net billed sales, including tax | **130.500** |
| Seller reconciliation | **58 Admin + 58 active rep + 14.5 inactive rep** |
| Net tax | 18.000 |
| Net billed sales excluding tax | 112.500 |
| Gross cash collections / cash refunds | 168.000 / 42.000 |
| Net cash collections | **126.000** |
| Receivables | **4.500** |

Thus **130.500 = 126.000 cash + 4.500 receivables**. Company cash was 116 and
representative cash 10. Initial invoice collections and later receipts are
distinct; receipts do not add sales. Returns retain their own dates and original
seller attribution. The active-representative UI table remains a subset of
company totals. `totalSales` is operational tax-inclusive net billed sales,
not tax-exclusive accounting revenue or cash collected.

## Preservation, configuration and synthetic fixtures

All original field values across **192 pre-existing documents**, the existing
Auth user, permissions and audit records were preserved. The only original
document whose hash changed was `companies/default_company/settings/app`, through
the addition of `documentSettings`; no original field was overwritten.

The initial provisioning document lacked numbering settings, which both the
original and reviewed Rules correctly rejected for invoice creation. The repair
persisted the same INV/REC/QUO/RET and other document defaults already used by
Flutter. It did not relax Rules or change existing permission/JoFotara values.
Audit event: **4016fb007b10053ea8ea02935f71e96780c512e16be11207f98193d0d69572a8**.

**18 new synthetic Auth users** and synthetic transactions/projections/audit
records remain for review. Posted history was never deleted or rewritten and
financial balances were changed only by existing trusted posting workflows.
The initial fixture used fixed display numbers; its harness now uses the normal
client allocator. A missing invoice counter was created through existing client
Rules to reserve the used synthetic number; the next invoice is **INV-2026-000002**.
Two synthetic transfer records retain display number TRN-2026-900001 with distinct
record IDs; their immutable posting/audit histories remain intact. This fixture
limitation does not duplicate their posting effects.

Neither protected Firebase project was accessed. No claim about independent
external changes to those projects is made. Maintenance rebuilds/backfills were
not executed; settlement journal/preflight code remains unchanged and outside
live posting. Accounting implementation remains at Phase 2B-5.

## Rollback and remaining limits

The previous Hosting version **c715e28bcb6fdd76** is retained and FINALIZED; all
40 downloadable assets were hash-verified, with its two managed Firebase assets
covered by the immutable version. Existing Function archives, full configuration,
Rules and index metadata were captured and verified. A tested, patched backend
fallback archive is retained. See the
[safe rollback plan](../.staging/fatoora-original-staging/current-release/rollback/safe-rollback-plan.json).
Retain secure Rules, additive indexes, numbering defaults and corrected posting;
do not redeploy vulnerable original Function archives or restore financial data.
No rollback drill or rollback release was performed.

Visual desktop/mobile and Arabic/English browser checks remain **BLOCKED**.
The browser host was unavailable, and the native fallback stopped because it
could not verify the browser URL sufficiently to enforce policy. The
[computer-use skill](<C:/Users/osama aljayatweh/.codex/plugins/cache/openai-bundled/computer-use/26.1103.32239/skills/computer-use/SKILL.md>)
references [guidance](<C:/Users/osama aljayatweh/.codex/plugins/cache/openai-bundled/computer-use/26.1103.32239/docs/guidance.md>)
requiring: “If Computer Use reports that the turn ended … stop issuing app input.”
No further UI input was attempted. API and asset verification do not establish
visual acceptance.

Existing mixed-source cash-refund restrictions and operational reporting filters
remain. These checks do not complete a tax/COGS general ledger or authorize
historical financial corrections. All manifests, exact runtime trees, checks and
acceptance receipts are retained under
[current-release](../.staging/fatoora-original-staging/current-release/).
