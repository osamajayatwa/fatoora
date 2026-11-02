# Production access diagnosis and investigation status

Date: 2026-11-02, Asia/Amman. Repository: `C:\src\fatoora`.
Approved project: `fatoora-6b192`. Production access: strictly read-only.

## Outcome

**BLOCKED by local outbound network access denial. Not resolved in this execution context.**

The user's bounded production investigation is approved. The earlier approval
block in the original inventory/financial audit is no longer the access blocker.
The current blocker occurs before a Google API response. No production records
were retrieved, inspected, retained, or exported. No production discrepancy,
affected invoice ID, historical root cause, or correction amount is established.

## Evidence from this diagnostic session

| Layer | Observed result | Interpretation |
|---|---|---|
| Repository target | Production/default alias is `fatoora-6b192` | Expected project; no alias change |
| SDK initialization | Existing audit utility uses Firebase Admin `applicationDefault()` outside emulation | Firebase CLI/browser sign-in and SDK ADC are separate access paths |
| Runtime overrides | No Firestore/Auth emulator, explicit credential override, project override, proxy, or custom CA variables set in the inspected process | No observed accidental emulator routing or environment override |
| Existing SDK authentication | `GoogleAuth.getClient()` returns `UserRefreshClient` in 4 ms | Existing user ADC is discoverable; no credential values were inspected or printed |
| DNS | Firestore and OAuth endpoints both resolve, each with two addresses | DNS resolution succeeds |
| HTTPS to `firestore.googleapis.com` | `EACCES`, 15 ms | Local outbound connection denied; no HTTP/API response |
| HTTPS to `oauth2.googleapis.com` | `EACCES`, 5 ms | Credential-refresh endpoint also inaccessible |
| HTTP/2 to Firestore | `EACCES`, 5 ms | Failure is not isolated to the gRPC/HTTP2 transport |
| Existing-authentication read-only SDK probe | `EACCES`, failing host `oauth2.googleapis.com`, 715 ms, HTTP status absent | Failure occurs while the SDK attempts credential refresh, before a Firestore result |
| Firebase CLI state-directory metadata | Access denied in the restricted execution context | Separate local CLI access limitation; no attempt was made to read/copy CLI tokens |
| Browser connector | Zero browser surfaces; `The browser access host is unavailable` | No independently verifiable Firebase Console tab is available to this tool |

The failing SDK probe used the installed Google OAuth client with existing ADC.
Its only proposed database operation was `documents:runQuery`: an exact `name ==
Jihad` user-profile query, limit 1, projecting UID, role and company only. This is
a read operation despite the HTTP POST method. It returned no records. Output
included only error codes, failing hostname, duration and record count; no
credentials, headers, response bodies or profile details were logged.

### Cause of the previous apparent SDK timeout

The previous caller imposed a 15-second outer deadline on a Firestore query.
That deadline reported `READ_TIMEOUT` without exposing the failing connection
stage. Current isolated probes establish an access denial, and the SDK
authentication request identifies the OAuth endpoint as the failing step.
This explains a reproducible connection blocker consistent with that timeout;
the original gRPC request's internal error was not captured, so attributing that
earlier request to the identical internal step remains an inference.
Increasing the outer query timeout cannot remove an outbound access denial.
The previous `CLIENT_TERMINATED` exception followed timeout cleanup and is not
evidence of a production Firestore error.

The established connection failure is **local network access denied (`EACCES`)**.
The specific enforcing component—execution sandbox/network policy versus an OS
network control—is not exposed by these probes and was not changed. This session
did not request elevated execution, alter firewall/proxy settings, change IAM or
Firestore rules, create credentials/accounts, or retry through an unverifiable
browser window.

### Authentication and permissions remain distinct

Discovering a `UserRefreshClient` establishes that existing credentials can be
loaded. It does not establish that their refresh token is currently valid, that
the account has the needed project permissions, or that a query is authorized.
Those checks require a reachable API. No HTTP 401/403 or Firestore
`PERMISSION_DENIED` response was received, so none of these is the verified cause
of this connection failure.

Local client rules restrict user-profile listing to the approved administrator
path and protect invoice/custody/financial reads by role and ownership. These
rules were inspected locally, not fetched from production. They cannot explain
a local outbound socket denial. Deployed rules, IAM access and token validity
remain unverified; no security change is recommended to resolve this evidence.

The previously reported browser URL-verification failure is a separate tool
safety boundary. This session checked only browser availability metadata. It did
not attempt native-window input, guess the current URL from a window title,
extract browser authentication, or bypass that boundary.

## Production investigation coverage

| Record category | Actual production records inspected |
|---|---:|
| Representative profiles | 0 |
| Invoices (approved ceiling: 200) | 0 |
| Custody movements / balances / transfers | 0 |
| Returns / linked audit events | 0 |
| Necessary customer / cash / journal records | 0 |
| **Total** | **0** |

Confirmed production inventory discrepancies: **undetermined**.
Confirmed production financial discrepancies: **undetermined**.
Affected invoice IDs and expected/actual quantities: **not established**.
Independent historical quantity reconstruction: **not performed**.

The earlier local defects and passing synthetic regression evidence remain in
`inventory_financial_integrity_audit.md`. They are not proof that Jihad's real
invoice was affected or that production balances are correct. No complete
synthetic audit was repeated for this access investigation.

## Safe user-assisted connection procedure

1. In your usual, already authorized **non-administrator** development terminal,
   use the existing SDK credentials and run:

   ```powershell
   Set-Location C:\src\fatoora\functions
   node scripts/diagnose_readonly_production_access.js --project=fatoora-6b192 --probe-read
   ```

   The script does not sign in, create/modify credentials, change configuration,
   write to Firestore, or export records. It uses the installed Google SDK's
   existing user ADC. It refuses emulator/explicit credential-file overrides.
   It checks DNS/HTTPS/HTTP2 and authentication discovery. If networking permits,
   it performs one bounded read-only profile query and prints only status/counts.
   If local probes already return `EACCES`/`EPERM`, it stops before that query.

2. Interpret the sanitized result:
   - `API_RESPONSE` with HTTP 200 proves that this bounded read worked in that
     terminal. Zero matching profiles does not prove Jihad is absent; his stored
     name/UID still needs scoped identification.
   - `EACCES`/`EPERM` before HTTP means that execution context still lacks a
     permitted outbound connection. The environment owner must provide an
     approved connection path; do not disable protections or request broader IAM.
   - Missing ADC or HTTP 401 requires the account owner to resolve the existing
     authenticated session through their normal approved process. Do not send
     token values, credential files, passwords or login codes to the agent.
   - HTTP 403/`PERMISSION_DENIED` requires reviewing the existing account's access
     through the authorized project owner. Do not grant additional privileges or
     modify rules as part of this investigation.

3. Share only the probe's sanitized status/count output. A successful probe in
   your terminal does not itself give the restricted agent process network
   access. Resume only after a permitted existing SDK connection is available to
   the agent, or the browser connector exposes an independently verified
   `https://console.firebase.google.com/` tab for this project. Restore the normal
   connector/session through the application's supported user workflow; do not
   bypass URL-verification restrictions or export browser authentication.

4. Once access is legitimately available, resume the already approved scope:
   identify Jihad, inspect at most 200 relevant invoices, trace their linked
   custody/transfers/returns/audit records and necessary financial effects, and
   reconstruct quantities through a stated read cutoff. Stop for explicit
   approval if additional records or broader access are needed. Keep production
   evidence outside Git and avoid unnecessary customer details.

## Correction recommendations and remaining gaps

No invoice-specific production correction can be justified yet. No repair script,
stock compensation quantity, financial adjustment amount, or deployment is
authorized by this report. Any later proposal must identify exact original
source/movement IDs, independently establish expected versus actual effects,
explain downstream dependencies and obtain separate approval for linked,
idempotent compensating transactions. Do not replay invoice confirmation or edit
balances merely because a local fix exists.

Remaining gaps are the real representative identity, invoice attribution/status,
tracking policy at posting, complete movement chronology/openings, persisted
custody balances, return/refund allocations, related financial effects, deployed
posting version and any actual historical impact of the reproduced defects.

Verification of this follow-up tool: JavaScript syntax and `--help` only. The
production SDK probe and network diagnostics above were executed separately with
sanitized output. No production mutations or additional access attempts were
performed after the connection and browser blockers were established.
