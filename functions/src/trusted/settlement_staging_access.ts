import {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {SettlementReadTarget, assertApprovedSettlementReadTarget, SETTLEMENT_STAGING_COMPANY} from "./settlement_read_target";
import type {SettlementReadPrincipal} from "./settlement_transport";

export const SETTLEMENT_PILOT_CONTROL_PATH = "internal_read_controls/settlement_breakdown";
export const SETTLEMENT_STAGING_APPS = Object.freeze([
  "1:5438538531:web:1fb5d6aac646d3b1240296", "1:5438538531:android:560f7feecdb97bf5240296",
]);
/** Security configuration only: never currency, balances, source or allocations.
 * It must be inaccessible to client Rules. No control result is cached. */
export function validateSettlementPilotControl(value: unknown, principal: SettlementReadPrincipal, now: number): string {
  const c = value as Record<string, unknown> | undefined;
  const deny = () => {throw new HttpsError("permission-denied", "Settlement pilot is unavailable.");};
  if (!c || Object.keys(c).sort().join(",") !== "allowedAppIds,allowedUids,companyId,enabled,expiresAtMillis,revision,schemaVersion" ||
      c.schemaVersion !== 1 || c.enabled !== true || c.companyId !== SETTLEMENT_STAGING_COMPANY ||
      typeof c.revision !== "string" || !/^[a-f0-9]{64}$/.test(c.revision) ||
      !Number.isSafeInteger(c.expiresAtMillis) || Number(c.expiresAtMillis) <= now || Number(c.expiresAtMillis) > now + 86400000 ||
      !Array.isArray(c.allowedUids) || c.allowedUids.length < 1 || c.allowedUids.length > 3 || new Set(c.allowedUids).size !== c.allowedUids.length ||
      c.allowedUids.some(uid => typeof uid !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) || !c.allowedUids.includes(principal.uid) ||
      !Array.isArray(c.allowedAppIds) || c.allowedAppIds.length < 1 || c.allowedAppIds.length > 2 || new Set(c.allowedAppIds).size !== c.allowedAppIds.length ||
      c.allowedAppIds.some(app => !SETTLEMENT_STAGING_APPS.includes(app)) || !c.allowedAppIds.includes(principal.appId)) return deny();
  return c.revision;
}
export function createSettlementPilotAccess(db: Firestore, target: SettlementReadTarget, clock: () => number = Date.now) {
  return async (principal: SettlementReadPrincipal) => {
    assertApprovedSettlementReadTarget(db, target);
    const snap = await db.doc(SETTLEMENT_PILOT_CONTROL_PATH).get();
    // The SDK version is part of the revision: any edit invalidates old sessions,
    // even when an operator accidentally reuses the visible revision field.
    return `${validateSettlementPilotControl(snap.data(), principal, clock())}:${snap.updateTime!.seconds}:${snap.updateTime!.nanoseconds}`;
  };
}
