# RC1 controlled staging deployment: stopped at artifact gate

Date: 2026-11-08, Asia/Amman.

**Status: BLOCKED at gate 1. No deployment or rollback was attempted.**

The user authorized the existing verified RC1 for `fatoora-original-staging`
(`5438538531`) only. That authorization remains recorded in the conversation;
another approval is not needed merely to resume verification of that same artifact.
The frozen candidate's earlier release hold is not the reason for this stop.

## Gate results

| Check | Result |
| --- | --- |
| Exact sealed RC1 archive/directory | BLOCKED: absent |
| RC1 `SHA256SUMS.json` | BLOCKED: absent; the candidate verifier reports ENOENT |
| Approved readiness receipt and archive-checksum receipt | BLOCKED: absent |
| Staging Android/Web SDK configuration | PASS: hashes match durable provisioning state; project, confirmation, project number and app registrations match |
| Protected local files | PASS: `.firebaserc`, `firebase.json`, `lib/firebase_options.dart`, production Android SDK configuration and Functions exports match the retained preflight hashes |
| Current remote revisions and index readiness | NOT RUN: stopped before cloud requests after the artifact gate failed |
| Live acceptance, Web/Android UI and financial reconciliation | NOT RUN |

The workspace, durable staging artifact cache and the user's Downloads, Desktop
and Documents were searched for RC1/archive/receipt candidates. The approved
artifact was not found. The remaining durable archives are the original staging
Functions sources, not the approved reassignment/return RC1. No candidate was
rebuilt, substituted or deployed from the mutable working tree.

## Exact deployment effect

- Indexes created/updated/deleted: **0 / 0 / 0**.
- Rules releases: **0**.
- Functions revisions: **0**, including `confirmSalesReturn` and all unrelated services.
- Hosting releases: **0**.
- Android installations/distributions/production builds: **0**.
- Auth, IAM, staging business-data or financial-record mutations: **0**.
- Synthetic staging transactions and historical corrections: **0**.
- Remote requests to staging or either protected Firebase project: **0**.

Both protected projects and unrelated staging resources were untouched by this
attempt. Their current remote fingerprints were not revalidated; no claim of
external-state equivalence since the earlier review is made.

## Recovery prerequisite

Restore the exact approved archive:

`reassignment-returns-20261108-rc1.zip`

Previously verified archive SHA-256:

`e21086a1f3b56c60d1e77b43ae773912462fecb437e12b7a38a572b8caac058b`

Previously verified `rc1/SHA256SUMS.json` SHA-256:

`b4159cfcfc4ced32ffffab3d65a69323c14df93996ea5ee6a79a704d345321e7`

The archive contains the sealed candidate, readiness receipt, approved Web/APK,
dependency evidence and rollback bundle. After restoration, verify the archive
and every manifest entry, then obtain a fresh remote baseline before the first
mutation. Do not regenerate a replacement and label it as this approved RC1.

The intended scope remains 32 additive indexes, the reviewed Rules,
`confirmSalesReturn` only in `us-central1`, the existing staging Hosting site and
the approved staging debug APK. Existing indexes and financial history must remain
intact. Full rollback readiness is unverified because the sealed rollback bundle
is also missing; the remaining old Functions archives alone are insufficient.
No rollback was needed or applied. Accounting implementation remains stopped.
