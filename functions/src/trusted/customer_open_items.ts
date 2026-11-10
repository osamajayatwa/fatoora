import {DocumentData, FieldValue, Firestore, Transaction} from "firebase-admin/firestore";
import type {AccountingDomainWrite, AccountingPostingContext} from "./accounting_posting";
import type {AccountingControlEffect} from "./accounting_controls";
import {AccountingJournalLine, JournalAccount, accountingDigest, accountingNeed, accountingSame, accountingUnits} from "./accounting_journal";
import {configurationDate, configurationId} from "./accounting_configuration_contract";
import {immutablePositionEvidence, verifyAccountingPosition} from "./accounting_positions";
import {assertAccountingControlContext, immutableAccountingRecord, selectOpenChargePositions} from "./accounting_transaction";
import {accountingDomainWitness, readAccountingEffects} from "./accounting_effects";
import {sumUnits} from "./exact_decimal";

export interface CustomerControlPlan {
  lines: AccountingJournalLine[]; controlEffects: AccountingControlEffect[];
  writes(binding: DocumentData): AccountingDomainWrite[];
}
export function configuredControlAccount(c: AccountingPostingContext, role: "receivables" | "customerCredits"): JournalAccount {
  const account = c.configuration.accounts.find(a => a.id === c.configuration.mappings[role]);accountingNeed(account, "Customer control mapping is missing.");
  return {...account, companyId: c.companyId, bookId: c.bookId, revisionId: c.revisionId, currency: c.configuration.currency, moneyScale: c.configuration.moneyScale};
}
function line(c: AccountingPostingContext, customerId: string, role: "receivables" | "customerCredits", amount: bigint, debit: boolean): AccountingJournalLine {
  return {id: role === "receivables" ? "customer-ar" : "customer-credit", account: configuredControlAccount(c, role),
    debitUnits: debit ? amount.toString() : "0", creditUnits: debit ? "0" : amount.toString(), dimensions: {customerId}};
}
function root(c: AccountingPostingContext): string {return `companies/${c.companyId}/books/${c.bookId}`;}
function stamp(c: AccountingPostingContext, data: DocumentData): DocumentData {
  return {...data, accountSequence: data.accountSequence + 1, accountingHeadEventId: c.eventId, updatedAt: FieldValue.serverTimestamp()};
}
async function party(tx: Transaction, db: Firestore, c: AccountingPostingContext, customerId: string) {
  assertAccountingControlContext(tx, c.companyId, c.bookId);
  configurationId(customerId, "customerId");
  const customer = (await tx.get(db.doc(`companies/${c.companyId}/customers/${customerId}`))).data();
  accountingNeed(customer?.id === customerId && customer.companyId === c.companyId && customer.active === true, "Customer is outside the company or inactive.");
  const path = `${root(c)}/party_positions/${customerId}`, ref = db.doc(path), snapshot = await tx.get(ref), d = snapshot.data();
  accountingNeed(d && d.id === customerId && d.companyId === c.companyId && d.bookId === c.bookId && d.customerId === customerId &&
    d.currency === c.configuration.currency && d.moneyScale === c.configuration.moneyScale && Number.isSafeInteger(d.accountSequence) && d.accountSequence >= 1 && d.accountSequence < Number.MAX_SAFE_INTEGER, "An explicit exact customer opening/position is required.");
  const ar = accountingUnits(d.receivableUnits), credit = accountingUnits(d.returnCreditUnits);
  accountingSame(d.signedDebtUnits, sumUnits([ar, -credit]).toString(), "Signed customer debt");
  await verifyAccountingPosition(tx, db, c, ref, d);
  return {path, data: d, ar, credit};
}
function effect(c: AccountingPostingContext, customerId: string, path: string, field: "receivableUnits" | "returnCreditUnits", before: bigint, after: bigint): AccountingControlEffect {
  const role = field === "receivableUnits" ? "receivables" : "customerCredits";
  return {kind: field === "receivableUnits" ? "receivable" : "customer_credit", accountId: c.configuration.mappings[role]!, dimensions: {customerId},
    positionPath: path, field, beforeUnits: before.toString(), afterUnits: after.toString()};
}
async function openItem(tx: Transaction, db: Firestore, c: AccountingPostingContext, id: string, customerId: string) {
  configurationId(id, "openItemId");const originalSnapshot = await tx.get(db.doc(`${root(c)}/open_items/${id}`));immutablePositionEvidence(originalSnapshot);
  const original = originalSnapshot.data()!, ref = db.doc(`${root(c)}/open_item_positions/${id}`), d = (await tx.get(ref)).data();
  accountingNeed(original.id === id && original.companyId === c.companyId && original.bookId === c.bookId && original.customerId === customerId &&
    original.currency === c.configuration.currency && original.moneyScale === c.configuration.moneyScale && ["charge", "return_credit"].includes(original.kind), "Open-item principal scope is invalid.");
  accountingNeed(d && d.id === id && d.companyId === c.companyId && d.bookId === c.bookId && d.customerId === customerId && d.kind === original.kind &&
    d.currency === original.currency && d.moneyScale === original.moneyScale && d.originalDate === original.originalDate && d.dueDate === original.dueDate &&
    Number.isSafeInteger(d.accountSequence) && d.accountSequence >= 1 && d.accountSequence < Number.MAX_SAFE_INTEGER, "Open-item position is missing or inconsistent.");
  const remaining = accountingUnits(d.remainingUnits);accountingNeed(remaining <= accountingUnits(original.originalUnits) && d.state === (remaining === 0n ? "closed" : "open"), "Open-item remaining amount/state is invalid.");
  const eventId = configurationId(original.accounting?.eventId, "original item event"), eventSnapshot = await tx.get(db.doc(`${root(c)}/events/${eventId}`)), event = immutableAccountingRecord(eventSnapshot);
  const witness = (await readAccountingEffects(tx, db, eventSnapshot, event)).find(e => e.path === originalSnapshot.ref.path && e.immutable);
  accountingNeed(witness && eventSnapshot.createTime!.isEqual(originalSnapshot.createTime!) && event.companyId === c.companyId && event.bookId === c.bookId, "Open-item principal has no atomic source event.", "data-loss");
  accountingSame(accountingDomainWitness(original), witness.document, "Immutable open-item principal");
  await verifyAccountingPosition(tx, db, c, ref, d);
  return {path: ref.path, data: d, remaining, original};
}

async function createItem(tx: Transaction, db: Firestore, c: AccountingPostingContext,
  input: {customerId: string; amountUnits: string; componentId: string; dueDate?: string; initialPaymentUnits?: string}, kind: "charge" | "return_credit"): Promise<CustomerControlPlan & {itemId: string}> {
  const amount = accountingUnits(input.amountUnits);accountingNeed(amount > 0n, "An open-item principal must be positive.");configurationId(input.componentId, "componentId");
  const p = await party(tx, db, c, input.customerId), itemId = `item_${accountingDigest([c.source, input.componentId, input.customerId])}`;
  const principalPath = `${root(c)}/open_items/${itemId}`, positionPath = `${root(c)}/open_item_positions/${itemId}`;
  accountingNeed((await tx.getAll(db.doc(principalPath), db.doc(positionPath))).every(s => !s.exists), "Open-item component already exists.");
  const dueDate = configurationDate(input.dueDate ?? c.accountingDate, "dueDate"), field = kind === "charge" ? "receivableUnits" : "returnCreditUnits";
  const paid = accountingUnits(input.initialPaymentUnits ?? "0");accountingNeed(paid <= amount && (kind === "charge" || paid === 0n), "Initial payment exceeds its invoice principal.");
  const remaining = amount - paid, before = kind === "charge" ? p.ar : p.credit, after = sumUnits([before, remaining]);
  const next = stamp(c, {...p.data, [field]: after.toString(), signedDebtUnits: sumUnits([kind === "charge" ? after : p.ar, -(kind === "return_credit" ? after : p.credit)]).toString()});
  const identity = {schemaVersion: 1, id: itemId, companyId: c.companyId, bookId: c.bookId, customerId: input.customerId,
    currency: c.configuration.currency, moneyScale: c.configuration.moneyScale, kind, originalDate: c.accountingDate, dueDate};
  const initialAllocationPath = `${root(c)}/allocations/allocation_${accountingDigest([c.source, itemId, "initial_payment"])}`;
  if (paid > 0n) accountingNeed(!(await tx.get(db.doc(initialAllocationPath))).exists, "Initial payment allocation already exists.");
  return {itemId, lines: [line(c, input.customerId, kind === "charge" ? "receivables" : "customerCredits", amount, kind === "charge"),
    ...(paid > 0n ? [{...line(c, input.customerId, "receivables", paid, false), id: "initial-payment-ar"}] : [])],
    controlEffects: [effect(c, input.customerId, p.path, field, before, after)], writes(binding) {
      return [{method: "create", path: principalPath, data: {...identity, originalUnits: amount.toString(), source: c.source, componentId: input.componentId, accounting: binding, createdAt: FieldValue.serverTimestamp()}},
        {method: "create", path: positionPath, data: {...identity, remainingUnits: remaining.toString(), state: remaining === 0n ? "closed" : "open", accountSequence: 1, accountingHeadEventId: c.eventId,
          accounting: binding, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}},
        {method: "set", path: p.path, data: next},
        ...(paid > 0n ? [{method: "create" as const, path: initialAllocationPath, data: {schemaVersion: 1, companyId: c.companyId, bookId: c.bookId,
          customerId: input.customerId, kind: "initial_payment", chargeItemId: itemId, amountUnits: paid.toString(), currency: c.configuration.currency,
          moneyScale: c.configuration.moneyScale, source: c.source, accounting: binding, createdAt: FieldValue.serverTimestamp()}}] : [])];
    }};
}
export function prepareCustomerCharge(tx: Transaction, db: Firestore, c: AccountingPostingContext,
  input: {customerId: string; amountUnits: string; componentId: string; dueDate: string; initialPaymentUnits?: string}) {
  accountingNeed(c.source.type === "invoices" || c.source.type === "opening_balances", "Charges require an invoice or evidenced opening source.");
  return createItem(tx, db, c, input, "charge");
}
export function prepareCustomerReturnCredit(tx: Transaction, db: Firestore, c: AccountingPostingContext,
  input: {customerId: string; amountUnits: string; componentId: string}) {
  accountingNeed(c.source.type === "sales_returns", "Return credits require the existing sales-return source.");
  return createItem(tx, db, c, input, "return_credit");
}

async function allocate(tx: Transaction, db: Firestore, c: AccountingPostingContext, input: {customerId: string; amountUnits: string; creditItemId?: string}): Promise<CustomerControlPlan> {
  const amount = accountingUnits(input.amountUnits);accountingNeed(amount > 0n, "Allocation must be positive.");
  const p = await party(tx, db, c, input.customerId), credit = input.creditItemId ? await openItem(tx, db, c, input.creditItemId, input.customerId) : null;
  accountingNeed(amount <= p.ar, "Allocation exceeds customer receivables.");
  if (credit) accountingNeed(credit.data.kind === "return_credit" && amount <= credit.remaining && amount <= p.credit && credit.data.originalDate <= c.accountingDate, "Credit is unavailable or predates its source.");
  else accountingNeed(amount <= p.ar - p.credit, "Ordinary receipts cannot exceed positive signed customer debt.");
  const candidates = await selectOpenChargePositions(tx, c.companyId, c.bookId, input.customerId), selected: {item: Awaited<ReturnType<typeof openItem>>; units: bigint}[] = [];
  let left = amount;
  for (const snapshot of candidates.slice(0, 100)) {
    if (left === 0n) break;
    const item = await openItem(tx, db, c, snapshot.id, input.customerId);
    accountingNeed(item.data.kind === "charge" && item.remaining > 0n && item.data.originalDate <= c.accountingDate, "Allocation candidate is invalid for this business date.");
    const units = left < item.remaining ? left : item.remaining;selected.push({item, units});left -= units;
  }
  accountingNeed(left === 0n, "Receipt allocation exceeds the bounded oldest-due coverage; no cash can post partially.");
  const arAfter = sumUnits([p.ar, -amount]), creditAfter = credit ? sumUnits([p.credit, -amount]) : p.credit;
  const nextParty = stamp(c, {...p.data, receivableUnits: arAfter.toString(), returnCreditUnits: creditAfter.toString(), signedDebtUnits: sumUnits([arAfter, -creditAfter]).toString()});
  const effects = [effect(c, input.customerId, p.path, "receivableUnits", p.ar, arAfter)];
  if (credit) effects.push(effect(c, input.customerId, p.path, "returnCreditUnits", p.credit, creditAfter));
  const ids = selected.map(({item}) => `allocation_${accountingDigest([c.source, item.data.id, credit?.data.id ?? null])}`);
  accountingNeed((await tx.getAll(...ids.map(id => db.doc(`${root(c)}/allocations/${id}`)))).every(s => !s.exists), "Allocation identity already exists.");
  return {lines: [...(credit ? [line(c, input.customerId, "customerCredits", amount, true)] : []), line(c, input.customerId, "receivables", amount, false)], controlEffects: effects,
    writes(binding) {
      const writes: AccountingDomainWrite[] = [{method: "set", path: p.path, data: nextParty}];
      selected.forEach(({item, units}, i) => {
        const remaining = item.remaining - units;
        writes.push({method: "set", path: item.path, data: stamp(c, {...item.data, remainingUnits: remaining.toString(), state: remaining === 0n ? "closed" : "open"})},
          {method: "create", path: `${root(c)}/allocations/${ids[i]}`, data: {schemaVersion: 1, id: ids[i], companyId: c.companyId, bookId: c.bookId,
            customerId: input.customerId, kind: credit ? "credit_application" : "receipt_allocation", chargeItemId: item.data.id, creditItemId: credit?.data.id ?? null,
            amountUnits: units.toString(), currency: c.configuration.currency, moneyScale: c.configuration.moneyScale, source: c.source, accounting: binding, createdAt: FieldValue.serverTimestamp()}});
      });
      if (credit) {const remaining = credit.remaining - amount;writes.push({method: "set", path: credit.path, data: stamp(c, {...credit.data, remainingUnits: remaining.toString(), state: remaining === 0n ? "closed" : "open"})});}
      return writes;
    }};
}
export function prepareCustomerReceipt(tx: Transaction, db: Firestore, c: AccountingPostingContext, input: {customerId: string; amountUnits: string}) {
  accountingNeed(c.source.type === "receipts", "Collections require the existing receipt source.");return allocate(tx, db, c, input);
}
export function prepareCustomerCreditApplication(tx: Transaction, db: Firestore, c: AccountingPostingContext, input: {customerId: string; amountUnits: string; creditItemId: string}) {
  return allocate(tx, db, c, input);
}

export async function prepareCustomerReceivableReduction(tx: Transaction, db: Firestore, c: AccountingPostingContext,
  input: {customerId: string; amountUnits: string; chargeItemId: string}): Promise<CustomerControlPlan> {
  accountingNeed(c.source.type === "sales_returns", "Receivable reductions require the existing sales-return source.");
  const amount = accountingUnits(input.amountUnits), p = await party(tx, db, c, input.customerId), item = await openItem(tx, db, c, input.chargeItemId, input.customerId);
  accountingNeed(amount > 0n && item.data.kind === "charge" && amount <= item.remaining && amount <= p.ar && item.data.originalDate <= c.accountingDate, "Return receivable reduction exceeds eligible remaining debt.");
  const after = p.ar - amount, remaining = item.remaining - amount, id = `allocation_${accountingDigest([c.source, item.data.id, "return_reduction"])}`;
  const path = `${root(c)}/allocations/${id}`;accountingNeed(!(await tx.get(db.doc(path))).exists, "Return reduction identity already exists.");
  return {lines: [line(c, input.customerId, "receivables", amount, false)], controlEffects: [effect(c, input.customerId, p.path, "receivableUnits", p.ar, after)], writes(binding) {
    return [{method: "set", path: p.path, data: stamp(c, {...p.data, receivableUnits: after.toString(), signedDebtUnits: sumUnits([after, -p.credit]).toString()})},
      {method: "set", path: item.path, data: stamp(c, {...item.data, remainingUnits: remaining.toString(), state: remaining === 0n ? "closed" : "open"})},
      {method: "create", path, data: {schemaVersion: 1, id, companyId: c.companyId, bookId: c.bookId, customerId: input.customerId, kind: "return_reduction",
        chargeItemId: item.data.id, amountUnits: amount.toString(), currency: c.configuration.currency, moneyScale: c.configuration.moneyScale,
        source: c.source, accounting: binding, createdAt: FieldValue.serverTimestamp()}}];
  }};
}

/** A partially paid return changes debt and credit liability in one party write. */
export async function prepareCustomerReturnControls(tx: Transaction, db: Firestore, c: AccountingPostingContext,
  input: {customerId: string; chargeItemId: string; receivableReductionUnits: string; creditUnits: string; componentId: string}): Promise<CustomerControlPlan> {
  const reduction = accountingUnits(input.receivableReductionUnits), credit = accountingUnits(input.creditUnits);
  accountingNeed(reduction + credit > 0n, "A return must have a known financial effect.");
  const plans: CustomerControlPlan[] = [];
  if (reduction > 0n) plans.push(await prepareCustomerReceivableReduction(tx, db, c, {customerId: input.customerId, amountUnits: reduction.toString(), chargeItemId: input.chargeItemId}));
  if (credit > 0n) plans.push(await prepareCustomerReturnCredit(tx, db, c, {customerId: input.customerId, amountUnits: credit.toString(), componentId: input.componentId}));
  const effects = plans.flatMap(p => p.controlEffects), partyPath = `${root(c)}/party_positions/${input.customerId}`;
  return {lines: plans.flatMap(p => p.lines), controlEffects: effects, writes(binding) {
    const all = plans.flatMap(p => p.writes(binding)), partyWrites = all.filter(w => w.path === partyPath);
    const merged = {...partyWrites[0].data};
    for (const effect of effects) merged[effect.field] = effect.afterUnits;
    merged.signedDebtUnits = sumUnits([BigInt(merged.receivableUnits), -BigInt(merged.returnCreditUnits)]).toString();
    return [...all.filter(w => w.path !== partyPath), {method: "set", path: partyPath, data: merged}];
  }};
}
