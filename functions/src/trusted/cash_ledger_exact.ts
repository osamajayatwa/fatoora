import {DocumentData, FieldValue, Firestore, Transaction} from "firebase-admin/firestore";
import type {AccountingDomainWrite, AccountingPostingContext} from "./accounting_posting";
import type {AccountingControlEffect} from "./accounting_controls";
import {accountingNeed, accountingSame, accountingUnits} from "./accounting_journal";
import {configurationId} from "./accounting_configuration_contract";
import {accountingDomainWitness, readAccountingEffects} from "./accounting_effects";
import {assertAccountingControlContext, immutableAccountingRecord} from "./accounting_transaction";
import {immutablePositionEvidence} from "./accounting_positions";
import {parseUnits, sumUnits} from "./exact_decimal";

export function compatibleExactNumber(units: bigint, scale: number): number | null {
  if (units > BigInt(Number.MAX_SAFE_INTEGER) || units < -BigInt(Number.MAX_SAFE_INTEGER)) return null;
  const number = Number(units) / 10 ** scale;
  try {return parseUnits(String(number), scale) === units ? number : null;} catch {return null;}
}
export interface ExactCashPosition {
  path: string; id: string; amountUnits: string; sequence: number; cashAccount: "company_cash" | "rep_cash";
  holderType: "company" | "representative"; holderUid: string;
}
export async function readExactCashPosition(tx: Transaction, db: Firestore, context: AccountingPostingContext,
  cashAccount: "company_cash" | "rep_cash", salesRepId = ""): Promise<ExactCashPosition> {
  assertAccountingControlContext(tx, context.companyId, context.bookId);
  accountingNeed(cashAccount === "company_cash" ? salesRepId === "" : !!salesRepId, "Treasury identity is invalid.");
  const representative = cashAccount === "rep_cash", id = representative ? `rep_${configurationId(salesRepId, "representative")}` : "company_cash";
  const path = `companies/${context.companyId}/cash_balances/${id}`, position = await tx.get(db.doc(path)), d = position.data();
  accountingNeed(d, "Exact cash opening/position is missing; zero cannot be assumed.");
  const expected = {companyId: context.companyId, cashAccount, treasuryAccountId: id, salesRepId,
    holderType: representative ? "representative" as const : "company" as const, holderUid: representative ? salesRepId : context.companyId,
    currency: context.configuration.currency, moneyScale: context.configuration.moneyScale};
  accountingSame(d.id, id, "Cash position identity");
  for (const [key, value] of Object.entries(expected)) accountingSame(d[key], value, `Cash position ${key}`);
  const units = accountingUnits(d.amountUnits), compatible = compatibleExactNumber(units, expected.moneyScale);
  if (compatible !== null) accountingNeed(typeof d.amount === "number" && Number.isFinite(d.amount) && parseUnits(String(d.amount), expected.moneyScale) === units, "Exact/numeric cash position differs.");
  else accountingNeed(d.amount === null && d.legacyAmountCoverage === "not_representable", "Unrepresentable legacy cash must be explicitly unavailable.");
  accountingNeed(Number.isSafeInteger(d.accountSequence) && d.accountSequence >= 1 && d.accountSequence < Number.MAX_SAFE_INTEGER, "A proven cash sequence is required.");
  const headId = configurationId(d.lastMovementId, "lastMovementId"), head = await tx.get(db.doc(`companies/${context.companyId}/cash_movements/${headId}`));immutablePositionEvidence(head);
  const h = head.data()!;
  for (const [key, value] of Object.entries(expected)) accountingSame(h[key], value, `Cash head ${key}`);
  accountingSame(h.id, headId, "Cash movement identity");accountingSame(h.accountSequence, d.accountSequence, "Cash sequence");
  const before = accountingUnits(h.balanceBeforeUnits), after = accountingUnits(h.balanceAfterUnits), amount = accountingUnits(h.amountUnits);
  accountingNeed((amount > 0n || h.syntheticOpening === true) && ["in", "out"].includes(h.direction), "Cash head has no proven effect.");
  accountingSame(sumUnits([before, h.direction === "in" ? amount : -amount]).toString(), after.toString(), "Cash head equation");
  accountingSame(after.toString(), units.toString(), "Cash position/head units");
  accountingNeed(position.updateTime!.isEqual(head.createTime!), "Cash head and position did not commit together.", "data-loss");
  if (h.accounting?.engine === "foundation-v1") {
    const eventId = configurationId(h.accounting.eventId, "cash event"), eventSnapshot = await tx.get(db.doc(`companies/${context.companyId}/books/${context.bookId}/events/${eventId}`));
    const event = immutableAccountingRecord(eventSnapshot), effects = await readAccountingEffects(tx, db, eventSnapshot, event);
    accountingNeed(event.companyId === context.companyId && event.bookId === context.bookId && eventSnapshot.createTime!.isEqual(head.createTime!), "Cash event scope/commit differs.", "data-loss");
    accountingSame(d.accountingHeadEventId, eventId, "Cash event head");
    const leg = effects.find(e => e.path === head.ref.path && e.immutable), balance = effects.find(e => e.path === path && !e.immutable);
    accountingNeed(leg && balance, "Cash leg/position is absent from its event manifest.", "data-loss");
    accountingSame(accountingDomainWitness(h), leg.document, "Cash movement witness");
    accountingSame(accountingDomainWitness(Object.fromEntries(Object.keys(balance.document).map(k => [k, d[k]]))), balance.document, "Cash position witness");
  } else {
    accountingNeed(h.syntheticOpening === true && h.bookId === context.bookId && h.cutoverDate === context.configuration.openingBoundary.cutoverDate && d.syntheticOpeningId === headId, "An explicit opening or canonical event is required.");
    const opening = await tx.get(db.doc(`companies/${context.companyId}/books/${context.bookId}/synthetic_openings/${headId}`));immutablePositionEvidence(opening);
    accountingNeed(opening.createTime!.isEqual(head.createTime!), "Synthetic cash opening is not atomic.", "data-loss");
    accountingSame(opening.data(), {companyId: context.companyId, bookId: context.bookId, treasuryAccountId: id, amountUnits: units.toString(),
      currency: expected.currency, moneyScale: expected.moneyScale, cutoverDate: h.cutoverDate, syntheticOnly: true}, "Synthetic cash opening");
  }
  return {path, id, amountUnits: units.toString(), sequence: d.accountSequence, cashAccount, holderType: expected.holderType, holderUid: expected.holderUid};
}

export async function prepareExactCashChange(tx: Transaction, db: Firestore, context: AccountingPostingContext,
  input: {cashAccount: "company_cash" | "rep_cash"; salesRepId?: string; direction: "in" | "out"; amountUnits: string; movementId: string}) {
  configurationId(input.movementId, "cash movement");accountingNeed(["in", "out"].includes(input.direction), "Cash direction is invalid.");
  const amount = accountingUnits(input.amountUnits);accountingNeed(amount > 0n, "Cash movement must be positive.");
  const lock = await tx.get(db.doc(`companies/${context.companyId}/maintenance_locks/cash_reconciliation`));
  accountingNeed(!lock.exists || lock.data()?.active === false, "Cash reconciliation is in progress.");
  const position = await readExactCashPosition(tx, db, context, input.cashAccount, input.salesRepId ?? "");
  if (position.holderType === "representative") {
    const profile = (await tx.get(db.doc(`users/${position.holderUid}`))).data();
    accountingNeed(profile?.companyId === context.companyId && profile.role === "sales_rep" && profile.active === true && profile.approvalStatus === "approved", "Cash custodian is not current and approved.");
  }
  const before = BigInt(position.amountUnits), after = sumUnits([before, input.direction === "in" ? amount : -amount]);
  accountingNeed(after >= 0n, "Insufficient exact cash balance.");
  const movementPath = `companies/${context.companyId}/cash_movements/${input.movementId}`;
  accountingNeed(!(await tx.get(db.doc(movementPath))).exists, "Cash movement identity already exists.");
  const effect: AccountingControlEffect = {kind: "cash", accountId: context.configuration.mappings[position.holderType === "company" ? "companyCash" : "representativeCash"]!,
    dimensions: {treasuryAccountId: position.id, holderType: position.holderType, holderUid: position.holderUid}, positionPath: position.path, field: "amountUnits", beforeUnits: before.toString(), afterUnits: after.toString()};
  return {position, effect, beforeUnits: before.toString(), afterUnits: after.toString(), writes(binding: DocumentData, extra: DocumentData = {}): AccountingDomainWrite[] {
    const scale = context.configuration.moneyScale, numeric = compatibleExactNumber(amount, scale), numericAfter = compatibleExactNumber(after, scale);
    const identity = {companyId: context.companyId, cashAccount: input.cashAccount, salesRepId: input.salesRepId ?? "", treasuryAccountId: position.id,
      holderType: position.holderType, holderUid: position.holderUid, currency: context.configuration.currency, moneyScale: scale, accountSequence: position.sequence + 1};
    return [{method: "create", path: movementPath, data: {...extra, ...identity, id: input.movementId, amount: numeric,
      amountUnits: amount.toString(), balanceBefore: compatibleExactNumber(before, scale), balanceAfter: numericAfter,
      balanceBeforeUnits: before.toString(), balanceAfterUnits: after.toString(), direction: input.direction,
      legacyAmountCoverage: numeric === null ? "not_representable" : "exact", sourceCollection: context.source.type, sourceId: context.source.id,
      accounting: binding, createdByUid: context.actor.uid, createdAt: FieldValue.serverTimestamp()}},
    {method: "set", merge: true, path: position.path, data: {...identity, id: position.id, amountUnits: after.toString(), amount: numericAfter,
      legacyAmountCoverage: numericAfter === null ? "not_representable" : "exact", lastMovementId: input.movementId, accountingHeadEventId: context.eventId, updatedAt: FieldValue.serverTimestamp()}}];
  }};
}
