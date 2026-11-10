import {DocumentData, DocumentReference, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import type {AccountingPostingContext} from "./accounting_posting";
import {accountingDigest, accountingNeed, accountingSame} from "./accounting_journal";
import {accountingDomainWitness, readAccountingEffects} from "./accounting_effects";
import {immutableAccountingRecord} from "./accounting_transaction";

export function immutablePositionEvidence(snapshot: {exists: boolean; createTime?: Timestamp; updateTime?: Timestamp}): void {
  accountingNeed(snapshot.exists && snapshot.createTime?.isEqual(snapshot.updateTime!), "Immutable position evidence is missing or overwritten.", "data-loss");
}

/** Verify the exact position projection, allowing unrelated master/display edits. */
export async function verifyAccountingPosition(tx: Transaction, db: Firestore, context: AccountingPostingContext,
  ref: DocumentReference, data: DocumentData, projectionKeys?: readonly string[], timestampField = "updatedAt"): Promise<Timestamp> {
  const eventId = data.accountingHeadEventId;
  if (eventId) {
    const eventSnapshot = await tx.get(db.doc(`companies/${context.companyId}/books/${context.bookId}/events/${eventId}`));
    const event = immutableAccountingRecord(eventSnapshot);
    accountingNeed(event.companyId === context.companyId && event.bookId === context.bookId, "Position head belongs to another book.", "data-loss");
    const effects = await readAccountingEffects(tx, db, eventSnapshot, event), witness = effects.find(e => e.path === ref.path && !e.immutable);
    accountingNeed(witness, "Position is absent from its canonical event.", "data-loss");
    const keys = projectionKeys ?? Object.keys(witness.document);
    accountingSame(accountingDomainWitness(Object.fromEntries(keys.map(k => [k, data[k]]))), witness.document, "Canonical position head");
    const stamp = data[timestampField];
    accountingNeed(stamp instanceof Timestamp && stamp.isEqual(eventSnapshot.data()!.recordedAt), "Position marker differs from its event's recorded time.", "data-loss");
    if (timestampField === "updatedAt") accountingNeed((await tx.get(ref)).updateTime!.isEqual(eventSnapshot.createTime!), "Customer position did not commit with its event.", "data-loss");
    return eventSnapshot.createTime!;
  } else {
    const openingId = data.syntheticOpeningId;
    accountingNeed(typeof openingId === "string" && /^[A-Za-z0-9_-]{1,96}$/.test(openingId), "An evidenced position opening is required; zero is never assumed.");
    const opening = await tx.get(db.doc(`companies/${context.companyId}/books/${context.bookId}/synthetic_openings/${openingId}`));immutablePositionEvidence(opening);
    const o = opening.data()!;
    accountingNeed(o.companyId === context.companyId && o.bookId === context.bookId && o.syntheticOnly === true && o.cutoverDate === context.configuration.openingBoundary.cutoverDate, "Synthetic opening scope/boundary is invalid.", "data-loss");
    const witness = o.positions?.[accountingDigest(ref.path)];accountingNeed(witness, "Position is missing from its explicit opening evidence.", "data-loss");
    const keys = projectionKeys ?? Object.keys(witness);
    accountingSame(accountingDomainWitness(Object.fromEntries(keys.map(k => [k, data[k]]))), witness, "Explicit opening position");
    const stamp = data[timestampField];
    accountingNeed(stamp instanceof Timestamp && stamp.isEqual(o.createdAt), "Opening position marker differs from its opening's recorded time.", "data-loss");
    if (timestampField === "updatedAt") accountingNeed((await tx.get(ref)).updateTime!.isEqual(opening.createTime!), "Customer opening position did not commit with its evidence.", "data-loss");
    return opening.createTime!;
  }
}
