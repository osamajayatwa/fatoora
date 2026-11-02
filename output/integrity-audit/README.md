# Audit evidence — synthetic data only

The report is [inventory_financial_integrity_audit.md](../../docs/audits/inventory_financial_integrity_audit.md).

All transaction data here was created in the local Firestore emulator under
`demo-fatoora-integrity-regression`, or other explicitly named synthetic test
projects. The `default_company` company ID in the lifecycle snapshot is a fixture
namespace. It is **not** an export from production.

| Evidence | Meaning |
|---|---|
| `node-baseline.log` | Original complete backend: 190 passing tests |
| `flutter-regression.log` | Original complete Flutter baseline: 411 passing tests |
| `integrity-before.log` | Initial new suite: 14 cases, 11 failing before corrections |
| `tracking-before.log` | Disabled-tracking custody bypass reproduced |
| `catalog-rules-before.log` | Catalog tracking/source changes incorrectly permitted |
| `decimal-before.log` | Decimal midpoint rounding defect reproduced |
| `missing-custody-before.log` | Missing projection silently restarts despite history |
| `legacy-return-before.log` | Prior return rounding drift and incomplete cached quantities reproduced (two failures) |
| `node-final.log` | Final complete backend suite: 223 passed, no failures/skips |
| `flutter-final.log` | Final complete Flutter suite: 423 passed |
| `flutter-analyze-final.log` | No static analysis issues |
| `flutter-web-build.log` | Local release web build with emulator/test configuration |
| `synthetic-lifecycle-snapshot.json` | Trusted operations' persisted source/balance/journal evidence |
| `synthetic-lifecycle-reconciliation.json` | Independent reconstruction: 51 comparisons, zero discrepancies/warnings |
| `verification_summary.json` | Machine-readable gate and test counts |
| `historical_scope_status.json` | Historical production verification explicitly blocked; no affected IDs guessed |

Re-run the offline comparison from the repository root:

```powershell
node functions/scripts/integrity_reconciliation.js output/integrity-audit/synthetic-lifecycle-snapshot.json
```

Intermediate setup/debug/failed iterative logs and local CLI configuration are
ignored. The retained before-fix failures are intentional regression evidence.
They are distinct from the final gates. No historical/live snapshot or credential
is part of this evidence package.
