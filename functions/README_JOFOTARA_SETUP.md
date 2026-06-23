# JoFotara Setup Placeholder

The Cloud Function code is intentionally incomplete and must not be used for real submissions until every official integration detail is confirmed.

Checklist for Osama:

- Get official JoFotara registration.
- Get User Number / Client ID.
- Get Secret Key.
- Confirm the official endpoint.
- Confirm whether the payload is XML, UBL, Base64, JSON, QR content, or another official format.
- Confirm all required headers.
- Confirm the test/sandbox environment.
- Add environment variables from `.env.example` using secure Firebase configuration.
- Test locally with the Firebase emulator.
- Keep `AppFeatureFlags.jofotaraEnabled = false` until the backend works end to end.
- Enable `AppFeatureFlags.jofotaraEnabled = true` only after successful backend testing.
- Deploy manually when ready.
- Never put secrets inside Flutter.
- Never commit real secrets to GitHub.

Security rules note:

- Users should create and read invoices only for companies they are authorized to access.
- Only authorized users should update invoices.
- Accepted electronic invoices should be protected from client-side editing when possible.
- Final invoice locking must also be enforced server-side, because client-side checks can be bypassed.

Important TODO markers in code:

- `// TODO: OSAMA ADD REAL JOFOTARA API URL HERE`
- `// TODO: OSAMA ADD REQUIRED HEADERS HERE`
- `// TODO: OSAMA MAP THE OFFICIAL XML/UBL PAYLOAD HERE`
- `// TODO: OSAMA HANDLE REAL RESPONSE FIELDS HERE`
