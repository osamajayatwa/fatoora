import {DocumentData, DocumentReference, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {configurationId, configurationRecord} from "./accounting_configuration_contract";
import {AccountingJournal, JournalAccount, accountingNeed, accountingTime, accountingUnits} from "./accounting_journal";
import {AccountingCommand, AccountingDomainWrite, AccountingPostingAdapter, postAccountingTransaction, recoverAccountingTransaction} from "./accounting_posting";
import {AccountingEmulatorOptions, inheritAccountingTransactionScope} from "./accounting_transaction";
import {parseUnits} from "./exact_decimal";
import {prepareCashSettlementWrite} from "./record_cash_settlement";

interface SettlementCommand extends AccountingCommand {semantic: {salesRepId: string; amountUnits: string; moneyScale?: number; notes: string}}
function command(input: unknown): SettlementCommand {
  const d = configurationRecord(input, "settlement", ["companyId", "bookId", "idempotencyKey", "operationId", "salesRepId", "amount", "amountUnits", "moneyScale", "settlementDate", "notes", "expectedConfigurationDigest"]);
  const companyId = configurationId(d.companyId, "companyId"), bookId = configurationId(d.bookId, "bookId"), operation = configurationId(d.operationId, "operationId");
  const sourceId = configurationId(`settlement_${operation}`, "settlementId"), salesRepId = configurationId(d.salesRepId, "salesRepId"), requestId = configurationId(d.idempotencyKey, "idempotencyKey");
  const scale = d.moneyScale ?? 3;
  accountingNeed(requestId.length >= 8 && Number.isSafeInteger(scale) && (scale as number) >= 0 && (scale as number) <= 6, "Explicit supported precision and a durable request key are required.", "invalid-argument");
  accountingNeed((d.amount === undefined) !== (d.amountUnits === undefined), "Supply one exact amount representation.", "invalid-argument");
  const amount = d.amountUnits === undefined ? parseUnits(d.amount as string, scale as number) : accountingUnits(d.amountUnits);
  accountingNeed(amount > 0n, "Settlement amount must be positive.", "invalid-argument");
  accountingNeed(d.notes === undefined || typeof d.notes === "string" && d.notes.length <= 1000, "Settlement notes are invalid.", "invalid-argument");
  return {companyId, bookId, requestId, expectedConfigurationDigest: d.expectedConfigurationDigest as string,
    source: {system: "fatoora", type: "settlements", id: sourceId, revision: "1", action: "rep_to_company_cash"}, businessTime: accountingTime(d.settlementDate),
    semantic: {salesRepId, amountUnits: amount.toString(), ...(scale === 3 ? {} : {moneyScale: scale as number}), notes: (d.notes as string | undefined)?.trim() ?? ""}};
}
function adapter(c: SettlementCommand): AccountingPostingAdapter {
  const root = `companies/${c.companyId}`, id = c.source.id;
  return {definitionId: "cash-settlements-v1", domainPaths: [`${root}/settlements/${id}`, `${root}/cash_movements/${id}_rep_out`, `${root}/cash_movements/${id}_company_in`,
    `${root}/cash_balances/rep_${c.semantic.salesRepId}`, `${root}/cash_balances/company_cash`, `${root}/financial_ledger_entries/settlement_${id}_transfer`],
    async prepare(tx, db, context) {
      accountingNeed((c.semantic.moneyScale ?? 3) === context.configuration.moneyScale, "Settlement precision differs from the pinned book.");
      const captured: AccountingDomainWrite[] = [];let collecting = false;
      const capture: Transaction = new Proxy(tx, {get(target, prop) {
        if (["create", "set", "update"].includes(String(prop))) return (ref: DocumentReference, data: DocumentData, options?: {merge?: boolean}) => {
          accountingNeed(collecting, "Domain writes must remain in their prepared closure.");
          captured.push({method: prop as AccountingDomainWrite["method"], path: ref.path, data, ...(prop === "set" ? {merge: options?.merge === true} : {})});return capture;
        };
        if (prop === "get" || prop === "getAll") return (...args: unknown[]) => {accountingNeed(!collecting, "Domain write closures cannot read.");return Reflect.apply(Reflect.get(target, prop), target, args);};
        const value = Reflect.get(target, prop, target);return typeof value === "function" ? value.bind(target) : value;
      }});
      inheritAccountingTransactionScope(capture, tx);
      const plan = await prepareCashSettlementWrite(capture, db, context.actor.uid, c.companyId, id.slice("settlement_".length),
        {salesRepId: c.semantic.salesRepId, settlementDate: new Timestamp(c.businessTime.seconds, c.businessTime.nanoseconds), notes: c.semantic.notes}, {context, amountUnits: c.semantic.amountUnits});
      accountingNeed(!plan.alreadyPosted, "A legacy source cannot be reposted into another accounting book.");
      function account(role: "companyCash" | "representativeCash"): JournalAccount {
        const configured = context.configuration.accounts.find(a => a.id === context.configuration.mappings[role]);accountingNeed(configured, "Cash account mapping is missing.");
        return {...configured, companyId: c.companyId, bookId: c.bookId, revisionId: context.revisionId, currency: context.configuration.currency, moneyScale: context.configuration.moneyScale};
      }
      const journal: AccountingJournal = {schemaVersion: 1, companyId: c.companyId, bookId: c.bookId, currency: context.configuration.currency,
        moneyScale: context.configuration.moneyScale, accountingDate: context.accountingDate, periodId: context.periodId, journalDefinitionId: context.definitionId,
        journalDefinitionRevisionId: context.definitionRevisionId, configurationDigest: context.configurationDigest, source: c.source,
        debitUnits: c.semantic.amountUnits, creditUnits: c.semantic.amountUnits, lines: [
          {id: "company-cash-in", account: account("companyCash"), debitUnits: c.semantic.amountUnits, creditUnits: "0", dimensions: {treasuryAccountId: "company_cash", holderType: "company", holderUid: c.companyId}},
          {id: "representative-cash-out", account: account("representativeCash"), debitUnits: "0", creditUnits: c.semantic.amountUnits, dimensions: {treasuryAccountId: `rep_${c.semantic.salesRepId}`, holderType: "representative", holderUid: c.semantic.salesRepId}}]};
      return {journal, controlEffects: plan.controlEffects, writes(binding) {
        accountingNeed(!collecting, "A domain plan can only be materialized once per attempt.");collecting = true;
        plan.write({immutableCreate: true, accountingBinding: binding});accountingNeed(captured.length === 6, "Settlement must retain its six original domain effects.");return captured;
      }};
    }};
}
export async function postFoundationCashSettlement(db: Firestore, uid: string | undefined, input: unknown, options: AccountingEmulatorOptions = {}) {
  const c = command(input);return postAccountingTransaction(db, uid, c, adapter(c), options);
}
export async function recoverFoundationCashSettlement(db: Firestore, uid: string | undefined, input: unknown, options: AccountingEmulatorOptions = {}) {
  const c = command(input);return recoverAccountingTransaction(db, uid, c, adapter(c), options);
}
