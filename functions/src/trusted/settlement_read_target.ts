import {Firestore, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

export const SETTLEMENT_STAGING_PROJECT = "fatoora-original-staging";
export const SETTLEMENT_STAGING_COMPANY = "default_company";
export const SETTLEMENT_STAGING_FLAG = "phase2b15-staging-pilot";
export const SETTLEMENT_READER_ACCOUNT = `fatoora-settlement-reader@${SETTLEMENT_STAGING_PROJECT}.iam.gserviceaccount.com`;
/** Opaque server capability. Never accepted from a request or persistence API. */
export interface SettlementReadTarget {readonly kind: "staging_read_only"}
const targets = new WeakMap<SettlementReadTarget, Firestore>();
const closed = () => new HttpsError("failed-precondition", "Approved settlement read target is unavailable.");

function pinned(db: Firestore) {
  const settings = Reflect.get(db, "_settings");
  if (!(db instanceof Firestore) || Reflect.get(db, "projectId") !== SETTLEMENT_STAGING_PROJECT || db.databaseId !== "(default)" ||
      settings?.servicePath !== "firestore.googleapis.com" || settings?.ssl === false || settings?.port !== undefined && settings.port !== 443 ||
      process.env.FATOORA_SETTLEMENT_READ_TRANSPORT !== SETTLEMENT_STAGING_FLAG ||
      process.env.GCLOUD_PROJECT !== SETTLEMENT_STAGING_PROJECT ||
      process.env.GOOGLE_CLOUD_PROJECT && process.env.GOOGLE_CLOUD_PROJECT !== SETTLEMENT_STAGING_PROJECT ||
      process.env.FATOORA_SETTLEMENT_RUNTIME_ACCOUNT !== SETTLEMENT_READER_ACCOUNT ||
      Object.entries(process.env).some(([k, v]) => v && (k.endsWith("_EMULATOR_HOST") ||
        ["FUNCTIONS_EMULATOR", "FIRESTORE_URL", "GOOGLE_APPLICATION_CREDENTIALS"].includes(k)))) throw closed();
}

export function createStagingSettlementReadTarget(db: Firestore): SettlementReadTarget {
  pinned(db);
  const target = Object.freeze({kind: "staging_read_only" as const});targets.set(target, db);return target;
}
export function assertApprovedSettlementReadTarget(db: Firestore, target: SettlementReadTarget, companyId?: string): void {
  if (targets.get(target) !== db || companyId !== undefined && companyId !== SETTLEMENT_STAGING_COMPANY) throw closed();
  pinned(db);
}
/** Firestore 7.11.6 creates no write batch for an SDK readOnly transaction.
 * Reject unsupported SDKs and writable/foreign transactions before any read.
 * Readers additionally trap mutation methods; IAM is the cloud write boundary. */
export function assertSettlementReadTransaction(tx: Transaction, db: Firestore, target: SettlementReadTarget): void {
  assertApprovedSettlementReadTarget(db, target);
  if (!(tx instanceof Transaction) || Reflect.get(tx, "_firestore") !== db || Reflect.get(tx, "_writeBatch") !== undefined ||
      Reflect.get(tx, "_maxAttempts") !== 1) throw closed();
}
