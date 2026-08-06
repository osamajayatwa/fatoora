import { HttpsError, onCall } from "firebase-functions/v2/https";

/**
 * Fail-closed placeholder retained only so an older deployment can be replaced
 * safely during the next Functions release. The callable is intentionally not
 * exported from index.ts and never reads or mutates an invoice.
 */
export const submitInvoiceToJoFotara = onCall(() => {
  throw new HttpsError(
    "failed-precondition",
    "JoFotara submission is disabled until the integration is production-ready.",
  );
});
