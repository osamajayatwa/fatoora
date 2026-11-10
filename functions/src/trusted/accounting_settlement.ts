import {DocumentData, DocumentReference, DocumentSnapshot, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {configurationId, configurationRecord} from "./accounting_configuration_contract";
import {AccountingJournal, JournalAccount, accountingNeed, accountingSame, accountingTime, accountingUnits} from "./accounting_journal";
import {AccountingCommand, AccountingDomainWrite, AccountingPostingAdapter, AccountingPostingContext, accountingDomainWitness, postAccountingTransaction, recoverAccountingTransaction} from "./accounting_posting";
import {AccountingEmulatorOptions, immutableAccountingRecord} from "./accounting_transaction";
import {decimalNumber, parseUnits, sumUnits} from "./exact_decimal";
import {prepareCashSettlementWrite} from "./record_cash_settlement";

interface SettlementCommand extends AccountingCommand {semantic: {salesRepId: string; amountUnits: string; notes: string}}
function command(input: unknown): SettlementCommand {
  const d = configurationRecord(input, "settlement", ["companyId", "bookId", "idempotencyKey", "operationId", "salesRepId", "amount", "settlementDate", "notes", "expectedConfigurationDigest"]);
  const companyId = configurationId(d.companyId, "companyId"), bookId = configurationId(d.bookId, "bookId");
  const operation = configurationId(d.operationId, "operationId"), sourceId = configurationId(`settlement_${operation}`, "settlementId");
  const salesRepId = configurationId(d.salesRepId, "salesRepId"), requestId = configurationId(d.idempotencyKey, "idempotencyKey");
  accountingNeed(requestId.length >= 8, "A durable request key is required.", "invalid-argument");
  accountingNeed(typeof d.amount === "string", "Settlement amount requires an exact decimal string.", "invalid-argument");
  const amount = parseUnits(d.amount, 3);accountingNeed(amount > 0n, "Settlement amount must be positive.", "invalid-argument");
  accountingNeed(d.notes === undefined || typeof d.notes === "string" && d.notes.length <= 1000, "Settlement notes are invalid.", "invalid-argument");
  return {companyId, bookId, requestId, expectedConfigurationDigest: d.expectedConfigurationDigest as string,
    source: {system: "fatoora", type: "settlements", id: sourceId, revision: "1", action: "rep_to_company_cash"},
    businessTime: accountingTime(d.settlementDate), semantic: {salesRepId, amountUnits: amount.toString(), notes: (d.notes as string | undefined)?.trim() ?? ""}};
}

interface ExactCash {path: string; id: string; amountUnits: string; sequence: number; holderType: string; holderUid: string; cashAccount: string}
function immutable(snapshot: DocumentSnapshot): void {
  accountingNeed(snapshot.exists && snapshot.createTime?.isEqual(snapshot.updateTime!), "Immutable treasury head/evidence is missing or overwritten.", "data-loss");
}
async function exactCash(tx: Transaction, db: Firestore, c: SettlementCommand, context: AccountingPostingContext, representative: boolean): Promise<ExactCash> {
  const id = representative ? `rep_${c.semantic.salesRepId}` : "company_cash", path = `companies/${c.companyId}/cash_balances/${id}`;
  const position = await tx.get(db.doc(path)), d = position.data();
  const expected = {id, companyId: c.companyId, cashAccount: representative ? "rep_cash" : "company_cash",
    treasuryAccountId: id, salesRepId: representative ? c.semantic.salesRepId : "", holderType: representative ? "representative" : "company",
    holderUid: representative ? c.semantic.salesRepId : c.companyId, currency: context.configuration.currency, moneyScale: 3};
  accountingNeed(d, "Exact cash opening/position is missing; zero cannot be assumed.");
  for (const [key, value] of Object.entries(expected)) accountingSame(d[key], value, `Treasury position ${key}`);
  const units = accountingUnits(d.amountUnits);accountingSame(parseUnits(String(d.amount), 3).toString(), units.toString(), "Legacy/exact cash position");
  accountingNeed(Number.isSafeInteger(d.accountSequence) && d.accountSequence >= 1 && d.accountSequence < Number.MAX_SAFE_INTEGER, "An evidenced cash sequence is required.");
  const headId = configurationId(d.lastMovementId, "lastMovementId"), head = await tx.get(db.doc(`companies/${c.companyId}/cash_movements/${headId}`));immutable(head);
  const h = head.data()!;
  for (const [key, value] of Object.entries(expected)) if (!["id"].includes(key)) accountingSame(h[key], value, `Treasury head ${key}`);
  accountingSame(h.id, headId, "Treasury movement identity");accountingSame(h.accountSequence, d.accountSequence, "Treasury sequence");
  const before = accountingUnits(h.balanceBeforeUnits), after = accountingUnits(h.balanceAfterUnits), amount = accountingUnits(h.amountUnits);
  accountingNeed(amount > 0n && (h.direction === "in" || h.direction === "out"), "Treasury head has no proven cash effect.");
  accountingSame(sumUnits([before, h.direction === "in" ? amount : -amount]).toString(), after.toString(), "Treasury head balance equation");
  accountingSame(after.toString(), units.toString(), "Treasury head/position units");
  accountingNeed(position.updateTime!.isEqual(head.createTime!), "Treasury head and position did not commit atomically.", "data-loss");
  if (h.accounting?.engine === "foundation-v1") {
    const eventId = configurationId(h.accounting.eventId, "head.eventId"), eventSnapshot = await tx.get(db.doc(`companies/${c.companyId}/books/${c.bookId}/events/${eventId}`));
    const event = immutableAccountingRecord(eventSnapshot);
    accountingNeed(event.companyId === c.companyId && event.bookId === c.bookId && eventSnapshot.createTime!.isEqual(head.createTime!), "Treasury head is outside this committed book.", "data-loss");
    accountingSame(d.accountingHeadEventId, eventId, "Treasury event head");
    const witness = event.effects.find((e: DocumentData) => e.path === head.ref.path && e.immutable);
    accountingNeed(witness, "Treasury head is absent from its event manifest.", "data-loss");
    accountingSame(accountingDomainWitness(h), witness.document, "Treasury event witness");
  } else {
    // This is synthetic acceptance evidence, never an inferred legacy opening.
    accountingNeed(h.syntheticOpening === true && h.bookId === c.bookId && h.cutoverDate === context.configuration.openingBoundary.cutoverDate && d.syntheticOpeningId === headId, "An explicit synthetic opening or canonical event is required.");
    const opening = await tx.get(db.doc(`companies/${c.companyId}/books/${c.bookId}/synthetic_openings/${headId}`));immutable(opening);
    accountingNeed(opening.createTime!.isEqual(head.createTime!), "Synthetic opening evidence is not atomic.", "data-loss");
    accountingSame(opening.data(), {companyId: c.companyId, bookId: c.bookId, treasuryAccountId: id,
      amountUnits: units.toString(), currency: context.configuration.currency, moneyScale: 3, cutoverDate: h.cutoverDate, syntheticOnly: true}, "Synthetic opening evidence");
  }
  return {path, id, amountUnits: units.toString(), sequence: d.accountSequence, holderType: expected.holderType, holderUid: expected.holderUid, cashAccount: expected.cashAccount};
}

function adapter(c: SettlementCommand): AccountingPostingAdapter {
  const root = `companies/${c.companyId}`, source = `${root}/settlements/${c.source.id}`;
  const out = `${root}/cash_movements/${c.source.id}_rep_out`, incoming = `${root}/cash_movements/${c.source.id}_company_in`;
  const legacy = `${root}/financial_ledger_entries/settlement_${c.source.id}_transfer`;
  const repPosition = `${root}/cash_balances/rep_${c.semantic.salesRepId}`, companyPosition = `${root}/cash_balances/company_cash`;
  return {definitionId: "cash-settlements-v1", domainPaths: [source, out, incoming, legacy, repPosition, companyPosition],
    async prepare(tx, db, context) {
      accountingNeed(context.configuration.moneyScale === 3, "The existing settlement bridge supports three monetary decimals.");
      const rep = await exactCash(tx, db, c, context, true), company = await exactCash(tx, db, c, context, false);
      const amount = BigInt(c.semantic.amountUnits), repAfter = sumUnits([BigInt(rep.amountUnits), -amount]), companyAfter = sumUnits([BigInt(company.amountUnits), amount]);
      accountingNeed(repAfter >= 0n, "Settlement exceeds the proven representative balance.");
      const captured: AccountingDomainWrite[] = [];let collecting = false;
      const capture = new Proxy(tx, {get(target, prop) {
        if (["create", "set", "update"].includes(String(prop))) return (ref: DocumentReference, data: DocumentData, options?: {merge?: boolean}) => {
          accountingNeed(collecting, "Domain writes must remain in their prepared write closure.");
          captured.push({method: prop as AccountingDomainWrite["method"], path: ref.path, data, ...(prop === "set" ? {merge: options?.merge === true} : {})});return capture;
        };
        if (prop === "delete") return () => {throw new Error("Financial source deletion is forbidden.");};
        if (prop === "get" || prop === "getAll") return (...args: unknown[]) => {
          accountingNeed(!collecting, "Domain write closures cannot read.");return Reflect.apply(Reflect.get(target, prop), target, args);
        };
        const value = Reflect.get(target, prop, target);return typeof value === "function" ? value.bind(target) : value;
      }});
      const numericAmount = decimalNumber(amount);
      const plan = await prepareCashSettlementWrite(capture, db, context.actor.uid, c.companyId, c.source.id.slice("settlement_".length),
        {salesRepId: c.semantic.salesRepId, amount: numericAmount, settlementDate: new Timestamp(c.businessTime.seconds, c.businessTime.nanoseconds), notes: c.semantic.notes});
      accountingNeed(!plan.alreadyPosted, "An existing legacy settlement cannot be reposted into a new accounting book.");
      function account(role: "companyCash" | "representativeCash"): JournalAccount {
        const configured = context.configuration.accounts.find(a => a.id === context.configuration.mappings[role]);
        accountingNeed(configured, "A trusted cash mapping is required.");
        return {...configured, companyId: c.companyId, bookId: c.bookId, revisionId: context.revisionId,
          currency: context.configuration.currency, moneyScale: 3};
      }
      const journal: AccountingJournal = {schemaVersion: 1, companyId: c.companyId, bookId: c.bookId,
        currency: context.configuration.currency, moneyScale: 3, accountingDate: context.accountingDate,
        periodId: context.periodId, journalDefinitionId: context.definitionId, journalDefinitionRevisionId: context.definitionRevisionId, configurationDigest: context.configurationDigest,
        source: c.source, debitUnits: c.semantic.amountUnits, creditUnits: c.semantic.amountUnits,
        lines: [{id: "company-cash-in", account: account("companyCash"), debitUnits: c.semantic.amountUnits, creditUnits: "0",
          dimensions: {treasuryAccountId: company.id, holderType: "company", holderUid: c.companyId}},
        {id: "representative-cash-out", account: account("representativeCash"), debitUnits: "0", creditUnits: c.semantic.amountUnits,
          dimensions: {treasuryAccountId: rep.id, holderType: "representative", holderUid: c.semantic.salesRepId}}]};
      return {journal, writes(binding) {
        accountingNeed(!collecting, "A domain write plan can only be materialized once per attempt.");collecting = true;
        plan.write({immutableCreate: true, accountingBinding: binding});
        accountingNeed(captured.length === 6, "The existing settlement writer must produce exactly six domain effects.");
        const byPath = new Map(captured.map(w => [w.path, w]));
        for (const [position, movementPath, after] of [[rep, out, repAfter], [company, incoming, companyAfter]] as const) {
          const leg = byPath.get(movementPath)!, balance = byPath.get(position.path)!;
          accountingNeed(leg && balance && leg.method === "create" && balance.method === "set" && balance.merge === true, "Existing treasury write shape changed.");
          for (const [field, expected] of [["amount", amount], ["balanceBefore", BigInt(position.amountUnits)], ["balanceAfter", after]] as const) {
            accountingSame(parseUnits(String(leg.data[field]), 3).toString(), expected.toString(), `Existing cash ${field}`);
          }
          accountingSame(parseUnits(String(balance.data.amount), 3).toString(), after.toString(), "Existing cash balance result");
          Object.assign(leg.data, {amountUnits: c.semantic.amountUnits, balanceBeforeUnits: position.amountUnits, balanceAfterUnits: after.toString(),
            currency: context.configuration.currency, moneyScale: 3, accountSequence: position.sequence + 1});
          Object.assign(balance.data, {amountUnits: after.toString(), currency: context.configuration.currency, moneyScale: 3,
            treasuryAccountId: position.id, holderType: position.holderType, holderUid: position.holderUid,
            accountSequence: position.sequence + 1, accountingHeadEventId: binding.eventId});
        }
        for (const path of [source, legacy]) Object.assign(byPath.get(path)!.data, {amountUnits: c.semantic.amountUnits, currency: context.configuration.currency, moneyScale: 3});
        return captured;
      }};
    },
  };
}

export async function postFoundationCashSettlement(db: Firestore, uid: string | undefined, input: unknown, options: AccountingEmulatorOptions = {}) {
  const c = command(input);return postAccountingTransaction(db, uid, c, adapter(c), options);
}
export async function recoverFoundationCashSettlement(db: Firestore, uid: string | undefined, input: unknown, options: AccountingEmulatorOptions = {}) {
  const c = command(input);return recoverAccountingTransaction(db, uid, c, adapter(c), options);
}
