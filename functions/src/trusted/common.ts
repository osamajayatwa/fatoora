import {
  DocumentData,
  DocumentReference,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {
  CallableOptions,
  CallableRequest,
  HttpsError,
} from "firebase-functions/v2/https";

export const REGION = "us-central1";
export const DEFAULT_COMPANY_ID = "default_company";

// Firebase client SDKs authenticate at the callable protocol layer. The
// underlying Cloud Run transport must accept the request before onCall can
// validate its Firebase ID token and populate request.auth.
export const TRUSTED_CALLABLE_OPTIONS: CallableOptions = {
  region: REGION,
  invoker: "public",
};

export function requireCallableUid(
  request: Pick<CallableRequest<unknown>, "auth">,
  functionName: string,
): string {
  const authenticated = request.auth != null;
  const uidPresent = typeof request.auth?.uid === "string" &&
    request.auth.uid.length > 0;
  logger.info("Trusted callable authentication state", {
    functionName,
    authenticated,
    uidPresent,
  });
  if (!uidPresent) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth!.uid;
}

export interface TrustedUser {
  uid: string;
  name: string;
  role: "admin" | "sales_rep";
  companyId: string;
}

export function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

export function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}

export function optionalString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function requiredIdempotencyKey(value: unknown): string {
  const key = requiredString(value, "idempotencyKey");
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(key)) {
    throw new HttpsError("invalid-argument", "idempotencyKey is invalid.");
  }
  return key;
}

export function finiteNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new HttpsError("invalid-argument", `${field} must be a number.`);
  }
  return value;
}

export function numberFrom(data: DocumentData, field: string): number {
  const value = data[field];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

export function roundMoney(value: number): number {
  if (!Number.isFinite(value)) {
    throw new HttpsError("invalid-argument", "A money value is invalid.");
  }
  return Math.round((value + Number.EPSILON) * 1000) / 1000;
}

export function roundQuantity(value: number): number {
  if (!Number.isFinite(value)) {
    throw new HttpsError("invalid-argument", "A quantity is invalid.");
  }
  return Math.round((value + Number.EPSILON) * 1000) / 1000;
}

export function timestampFrom(value: unknown, field: string): Timestamp {
  if (value instanceof Timestamp) return value;
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return Timestamp.fromDate(value);
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) return Timestamp.fromDate(date);
  }
  if (typeof value === "string") {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) return Timestamp.fromDate(date);
  }
  throw new HttpsError("invalid-argument", `${field} is invalid.`);
}

export async function requireTrustedUser(
  transaction: Transaction,
  firestore: Firestore,
  uid: string | undefined,
  requestedCompanyId: string,
): Promise<TrustedUser> {
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  const companyId = requiredString(requestedCompanyId, "companyId");
  const userSnapshot = await transaction.get(firestore.doc(`users/${uid}`));
  if (!userSnapshot.exists) {
    throw new HttpsError("permission-denied", "User profile was not found.");
  }
  const data = userSnapshot.data() ?? {};
  const role = optionalString(data.role);
  const userCompanyId = optionalString(data.companyId);
  if (
    data.active !== true ||
    data.approvalStatus !== "approved" ||
    (role !== "admin" && role !== "sales_rep") ||
    userCompanyId !== companyId
  ) {
    throw new HttpsError("permission-denied", "User is not approved for this company.");
  }
  return {
    uid,
    name: optionalString(data.name) || optionalString(data.email) || uid,
    role,
    companyId,
  };
}

export function requireDocumentAccess(
  user: TrustedUser,
  data: DocumentData,
): void {
  if (data.companyId !== user.companyId) {
    throw new HttpsError("permission-denied", "Document belongs to another company.");
  }
  if (
    user.role !== "admin" &&
    data.salesRepId !== user.uid &&
    data.createdByUid !== user.uid
  ) {
    throw new HttpsError("permission-denied", "Document is not owned by this user.");
  }
}

export function permissionValue(
  settings: DocumentData | undefined,
  field: string,
  fallback = true,
): boolean {
  const permissions = record(settings?.permissionSettings);
  const value = permissions[field];
  return typeof value === "boolean" ? value : fallback;
}

export function documentPrefix(
  settings: DocumentData | undefined,
  field: string,
  fallback: string,
): string {
  const documents = record(settings?.documentSettings);
  const value = optionalString(documents[field]).toUpperCase();
  return /^[A-Z0-9]{1,10}$/.test(value) ? value : fallback;
}

export async function allocateDocumentNumber(
  transaction: Transaction,
  firestore: Firestore,
  companyId: string,
  kind: string,
  date: Timestamp,
  prefix: string,
): Promise<{number: string; counterRef: DocumentReference; counterData: DocumentData}> {
  const year = date.toDate().getUTCFullYear();
  const counterRef = firestore.doc(
    `companies/${companyId}/counters/${kind}_${year}`,
  );
  const counter = await transaction.get(counterRef);
  const current = numberFrom(counter.data() ?? {}, "lastNumber");
  const next = Math.trunc(current) + 1;
  return {
    number: `${prefix}-${year}-${String(next).padStart(6, "0")}`,
    counterRef,
    counterData: {
      id: counterRef.id,
      companyId,
      year,
      lastNumber: next,
      prefix,
      updatedAt: FieldValue.serverTimestamp(),
    },
  };
}

export function businessPath(
  companyId: string,
  collection: string,
  id: string,
): string {
  return `companies/${companyId}/${collection}/${id}`;
}

export function deterministicId(prefix: string, idempotencyKey: string): string {
  return `${prefix}_${idempotencyKey}`;
}
