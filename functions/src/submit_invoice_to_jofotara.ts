import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { buildJofotaraPayload } from "./build_jofotara_payload";
import { invoiceDocumentPath } from "./firestore_paths";
import { InvoiceModel } from "./jofotara_types";

interface SubmitInvoiceRequest {
  companyId?: unknown;
  invoiceId?: unknown;
}

export const submitInvoiceToJoFotara = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const data = (request.data ?? {}) as SubmitInvoiceRequest;
  const companyId = readRequiredString(data.companyId, "companyId");
  const invoiceId = readRequiredString(data.invoiceId, "invoiceId");
  const firestore = getFirestore();
  const invoiceRef = firestore.doc(invoiceDocumentPath(companyId, invoiceId));

  let invoice: InvoiceModel | undefined;

  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(invoiceRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Invoice was not found.");
    }

    invoice = snapshot.data() as InvoiceModel;
    validateInvoiceForSubmission(invoice, companyId, invoiceId);

    transaction.update(invoiceRef, {
      invoiceStatus: "pendingSubmit",
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  if (!invoice) {
    throw new HttpsError("internal", "Invoice could not be loaded.");
  }

  const payload = buildJofotaraPayload(invoice);

  try {
    const response = await callJofotaraApiPlaceholder(payload);
    await invoiceRef.update({
      invoiceStatus: "accepted",
      isLocked: true,
      updatedAt: FieldValue.serverTimestamp(),
      government: {
        // TODO: OSAMA HANDLE REAL RESPONSE FIELDS HERE
        governmentInvoiceId: "",
        uuid: "",
        qrCode: "",
        submittedAt: Timestamp.now(),
        acceptedAt: Timestamp.now(),
        joFotaraStatus: "accepted",
        joFotaraErrorCode: "",
        joFotaraErrorMessage: "",
        rawResponse: response,
      },
    });

    return { ok: true, invoiceId };
  } catch (error) {
    logger.error("JoFotara placeholder submission failed", error);
    await invoiceRef.update({
      invoiceStatus: "rejected",
      isLocked: false,
      updatedAt: FieldValue.serverTimestamp(),
      government: {
        governmentInvoiceId: "",
        uuid: "",
        qrCode: "",
        submittedAt: Timestamp.now(),
        joFotaraStatus: "rejected",
        joFotaraErrorCode: "PLACEHOLDER_NOT_CONFIGURED",
        joFotaraErrorMessage:
          error instanceof Error ? error.message : "Submission failed.",
        rawResponse: {},
      },
    });
    throw new HttpsError(
      "internal",
      "JoFotara submission failed. Check backend setup placeholders.",
    );
  }
});

function readRequiredString(value: unknown, fieldName: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${fieldName} is required.`);
  }
  return value.trim();
}

function validateInvoiceForSubmission(
  invoice: InvoiceModel,
  companyId: string,
  invoiceId: string,
): void {
  if (invoice.companyId !== companyId || invoice.id !== invoiceId) {
    throw new HttpsError("failed-precondition", "Invoice path data mismatch.");
  }
  if (invoice.invoiceType !== "electronic") {
    throw new HttpsError(
      "failed-precondition",
      "Only electronic invoices can be submitted to JoFotara.",
    );
  }
  if (
    invoice.invoiceStatus !== "draft" &&
    invoice.invoiceStatus !== "rejected"
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Invoice must be draft or rejected before submission.",
    );
  }
  if (!invoice.invoiceNumber || !invoice.customerSnapshot) {
    throw new HttpsError(
      "failed-precondition",
      "Invoice number and customer snapshot are required.",
    );
  }
  if (!Array.isArray(invoice.items) || invoice.items.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "Invoice must contain at least one item.",
    );
  }
  if (!Number.isFinite(invoice.grandTotal) || invoice.grandTotal < 0) {
    throw new HttpsError("failed-precondition", "Invoice total is invalid.");
  }

  // TODO: OSAMA validate company tax fields before enabling real submission.
  // TODO: OSAMA validate customer tax fields according to official JoFotara rules.
  // TODO: OSAMA validate environment variables and official JoFotara setup.
}

async function callJofotaraApiPlaceholder(
  payload: string | Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const baseUrl = process.env.JOFOTARA_BASE_URL;
  const clientId = process.env.JOFOTARA_CLIENT_ID;
  const secretKey = process.env.JOFOTARA_SECRET_KEY;
  const taxpayerId = process.env.JOFOTARA_TAXPAYER_ID;
  const activityNumber = process.env.JOFOTARA_ACTIVITY_NUMBER;

  // TODO: OSAMA ADD REAL JOFOTARA API URL HERE
  // TODO: OSAMA ADD REQUIRED HEADERS HERE
  // TODO: OSAMA Confirm auth method and never place secrets in Flutter.
  void payload;
  void baseUrl;
  void clientId;
  void secretKey;
  void taxpayerId;
  void activityNumber;

  throw new Error(
    "JoFotara API call is still a placeholder. Configure official endpoint, headers, credentials, and payload mapping first.",
  );
}
