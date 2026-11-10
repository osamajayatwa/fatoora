import {Auth} from "firebase-admin/auth";
import {FieldPath, Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {SettlementReadTarget, assertApprovedSettlementReadTarget, assertSettlementReadTransaction} from "./settlement_read_target";
import {SETTLEMENT_PILOT_CONTROL_PATH} from "./settlement_staging_access";

const attempts = new WeakMap<Firestore, Promise<void>>();
/** Actual runtime proof of the four read grants. Three security-document reads
 * and one Auth get only: no company ledger scan, financial data or write probe.
 * A failed attempt remains closed until a fresh process is started. */
export function verifySettlementReadRuntime(db: Firestore, auth: Pick<Auth, "getUser">, target: SettlementReadTarget): Promise<void> {
  assertApprovedSettlementReadTarget(db, target);
  let attempt = attempts.get(db);
  if (!attempt) {
    attempt = (async () => {
      const ref = db.doc(SETTLEMENT_PILOT_CONTROL_PATH), control = await ref.get();
      const uid = control.data()?.allowedUids?.[0];
      if (!control.exists || typeof uid !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) throw new HttpsError("failed-precondition", "Reader security configuration unavailable.");
      const listed = await db.collection("internal_read_controls").where(FieldPath.documentId(), "==", "settlement_breakdown").select("schemaVersion").limit(1).get();
      if (listed.size !== 1 || listed.docs[0].ref.path !== ref.path) throw new HttpsError("failed-precondition", "Reader query permission unavailable.");
      await db.runTransaction(async tx => {
        assertSettlementReadTransaction(tx, db, target);
        if (!(await tx.get(ref)).exists) throw new HttpsError("failed-precondition", "Reader transaction permission unavailable.");
      }, {readOnly: true});
      if ((await auth.getUser(uid)).uid !== uid) throw new HttpsError("failed-precondition", "Reader Auth permission unavailable.");
    })();
    attempts.set(db, attempt);
  }
  return attempt;
}
