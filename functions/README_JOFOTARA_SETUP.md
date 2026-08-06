# JoFotara Integration (Disabled)

JoFotara submission is disabled. The callable is not exported from
`src/index.ts`; the retained replacement handler only returns
`failed-precondition` and performs no Firestore reads or writes. During the
next authorized Functions deployment, delete the previously deployed callable
or replace it with this fail-closed handler before any client feature is
enabled.

Checklist for Osama:

- Get official JoFotara registration.
- Get User Number / Client ID.
- Get Secret Key.
- Confirm the official endpoint.
- Confirm whether the payload is XML, UBL, Base64, JSON, QR content, or another official format.
- Confirm all required headers.
- Confirm the test/sandbox environment.
- Store future credentials in Firebase-managed secrets, never Flutter assets.
- Test locally with the Firebase emulator.
- Keep `AppFeatureFlags.jofotaraEnabled = false` until the backend works end to end.
- Enable `AppFeatureFlags.jofotaraEnabled = true` only after successful backend testing.
- Deploy only through the reviewed release process when ready.
- Never put secrets inside Flutter.
- Never commit real secrets to GitHub.

Required security work before re-enabling:

- Validate active/approved user, company, role, permission, and invoice owner.
- Require a confirmed eligible invoice and immutable request idempotency key.
- Keep submission attempts and external responses in an append-only audit log.
- Never change invoice status when the external request fails.
- Cover admin, representative, pending, inactive, wrong-company, wrong-owner,
  missing-invoice, duplicate, and external-failure cases with emulator tests.
