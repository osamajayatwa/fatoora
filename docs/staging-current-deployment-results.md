# Current application staging release: stopped at security gate

**Historical checkpoint, superseded by the completed
[current staging release report](staging-current-release-results.md).**

Date: 2026-11-08, Asia/Amman. Target: **fatoora-original-staging / 5438538531 only**.

**Deployment: BLOCKED. Dependency security gate: FAIL. Staging acceptance: NOT RUN.**
No deployment or cloud mutation was performed. The prior RC1 recovery process was
not resumed. This review uses the current working tree and fresh staging metadata.

| Verification | Result |
| --- | --- |
| Functions TypeScript build and installed runtime dependency tree | PASS |
| Backend regression suite, isolated Firestore emulator | PASS: 683 tests, zero failures/skips |
| Flutter regression suite | PASS: 573 tests |
| Flutter static analysis | PASS: no issues |
| Staging runtime and provisioning guards | PASS: five tests |
| Native/Dart staging registrations and protected local configuration | PASS |
| Current/deployed Functions compatibility | PASS: 35 endpoint definitions, runtime adapter, dependency lock and unrelated posting mappings unchanged |
| Runtime dependency advisory audit | FAIL: 17 affected package findings: one critical, five high, eleven moderate |
| Current indexes/native query planning | 268/268 READY; 42 existing-query plans pass, 42 history-query plans require the 32 additions |
| Full rollback artifact | BLOCKED: backend bytes verified; Hosting asset downloads time out |
| New Web release build, live synthetic acceptance and browser workflows | NOT RUN after the security stop |

## Security stop

The existing, unchanged Functions dependency lock contains `proxy-addr@2.0.7`,
through `firebase-functions@5.1.1 -> express@4.22.2`. Its
[maintainer advisory](https://github.com/jshttp/proxy-addr/security/advisories/GHSA-jqcg-44mw-7w3h)
is critical and identifies 2.0.8 as patched. Exploitation depends on particular
proxy-trust subnet configuration. No IP-based authorization or such subnet
configuration was found in Fatoora source; an application authentication bypass
has **not** been established. Cloud framework behavior has not been fully triaged.

The runtime tree also contains `body-parser@1.20.5`; its
[maintainer advisory](https://github.com/expressjs/body-parser/security/advisories/GHSA-27r3-jxmh-p828)
describes a high-severity unauthenticated compressed-request process crash and
identifies 1.20.9 as patched. Public Functions transport makes request parsing a
material availability concern. Actual cloud exploitability was not tested.
Other high findings concern `@fastify/busboy`, `@grpc/grpc-js`, `fast-xml-parser`
and `node-forge`. Findings require dependency remediation or documented,
deployment-specific mitigation before this gate can pass. No dependency upgrades,
security exceptions or live exploit probes were performed.

## Exact application scope when gates pass

1. Add the 32 reviewed `invoices` COLLECTION indexes; retain all 268 existing
   indexes and field overrides. Wait for readiness and all 84 native query plans
   to pass before activating the dependent application behavior.
2. Deploy **confirmSalesReturn only**, in `us-central1`, codebase
   `fatoora-original-staging`, preserving verified runtime/build identities and
   transport permissions. The other 34 Functions need no redeployment.
3. Publish the current reviewed Firestore Rules, then a fresh staging-configured
   Flutter Web build to the existing Hosting site. Use a frozen configuration
   without the old provisioning predeploy hooks, which rebuild an earlier source.

Source comparison found three changed backend modules: return posting, its ledger
mapper and the guarded offline rebuild mapper. Only
`buildSalesReturnFinancialLedgerEntries` changed among shared mapping functions.
The offline rebuild was never executed. Settlement preflight, journal intent,
cash-settlement writer and exported Functions are identical to deployed source.
Preflight remains internal/read-only and journal intent has no live writer path.
No experimental accounting functionality or incomplete electronic-tax integration
was enabled. No Android build or distribution is part of this attempt.

## Current revisions and rollback evidence

- `confirmSalesReturn`: **confirmsalesreturn-00002-guf**; source generation
  **1793826820049606**; build **66501cb2-2c1d-4715-92aa-fe1abff3a65d**.
- All 35 Functions are ACTIVE. Each exact deployed source object's generation,
  size and MD5 matches the retained source archive, SHA-256
  **6e38f98661aee08998d26c4b745d5ee3a1060c35ef164433d6ecbeed47f8b3ad**.
- Ruleset: **9945167a-b4da-40a6-a527-df26775474bb**.
- Hosting version: **c715e28bcb6fdd76**; release **1793828273153000**.
- Full Function configuration, source provenance, Rules source and index/Hosting
  metadata are retained in
  [rollback/baseline.json](../.staging/fatoora-original-staging/current-release/rollback/baseline.json).
  Backend source bytes and Rules are captured. Public Hosting asset retrieval
  failed with HTTPS timeouts, so the complete rollback bundle is not verified.
  IAM policy capture and rollback execution verification remain outstanding.
- No rollback was executed. Retained old code is evidence, not automatic approval
  to restore known incorrect refund posting or weaken Rules. Any rollback must
  preserve secure behavior, additive indexes, audit trails and financial history.

## Acceptance and accounting limits

Fresh local tests cover reassignment, history/statement access and revocation,
original seller attribution, partial/full returns, refunds, receipt cancellation,
cash provenance, inventory, permissions, reporting and reconciliation. They do
not substitute for real staging Auth/callable/Rules/trigger acceptance or browser
testing, which remain pending along with the new Web build.

Existing dashboards report return-adjusted **tax-inclusive billed sales**;
tax-exclusive revenue, tax, receipts, cash and receivables are separate measures.
Company reconciliation must include Admin and inactive sellers; the active-rep
table is only a subset. Later collections do not create sales. Historical customer
filters and operational projections are not a completed general-ledger control.
Double-entry accounting remains stopped at Phase 2B-5.

Cloud changes: **zero indexes, zero Rules releases, zero Functions revisions,
zero Hosting releases, zero Auth/IAM/data writes and zero synthetic staging
transactions**. Neither protected Firebase project was contacted. Their external
state was not fingerprinted. Existing staging business data was not written.

Evidence and hashes of 577 tested source inputs are retained under
[current-release](../.staging/fatoora-original-staging/current-release/).
Use the verification checkpoint to avoid rerunning unaffected checks; dependency
or source changes require their affected checks to be repeated. The existing
whitespace-only change in `lib/main.dart` was preserved; `git diff --check` reports
its trailing whitespace. No application source was edited during this attempt.
