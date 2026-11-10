import {DocumentData, Firestore, Transaction} from "firebase-admin/firestore";
import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {requireTrustedUser} from "./common";
import {companyCashAccount, repCashAccount} from "./financial_ledger";
import {buildSettlementJournalIntent, validateSettlementJournalIntent, SettlementJournalIntent, SettlementJournalIntentInput} from "./financial_ledger_mappings";
import {Time, Position, settlementReader, readSettlementBook, readSettlementMappings, readSettlementPositions,
  periodContains, need, eq, id, required, time, compare, money, freeze} from "./settlement_preflight_shared";

export interface SettlementPreflightInput {
  companyId: string;
  settlementId: string;
  expectedBookId?: string;
  expectedPreflightDigest?: string;
}
export interface SettlementPreflight {
  schemaVersion: 1;
  mode: "committed_settlement_read_only";
  preparedByUid: string;
  intent: SettlementJournalIntent;
  preflightDigest: string;
  context: {
    bookRevisionId: string;
    policyRevisionId: string;
    mappingRevisionId: string;
    legacyCurrencyBindingRevisionId: string | null;
    period: {id: string; revisionId: string; startsAt: Time; endsAt: Time};
  };
  positions: readonly Position[];
  sourceKey: {path: string; state: "absent" | "matching_binding"};
  timestamps: {
    accountingDate: Time;
    sourceRecordedAt: Time;
    sourceCommittedAt: Time;
    transactionReadTime: Time;
    journalCommittedAt: null;
  };
  observations: readonly {path: string; readTime: Time; updateTime: Time | null}[];
}

/** Internal read-only entry point; no callable or writer integration. */
export async function preflightSettlementTransaction(
  firestore: Firestore, uid: string | undefined, input: SettlementPreflightInput,
): Promise<SettlementPreflight> {
  return firestore.runTransaction(transaction => prepareSettlementPreflight(transaction, firestore, uid, input));
}

/** All reads belong to this attempt and must precede caller-owned writes. */
export async function prepareSettlementPreflight(
  transaction: Transaction, firestore: Firestore, uid: string | undefined, input: SettlementPreflightInput,
): Promise<SettlementPreflight> {
  const companyId = id(input?.companyId, "companyId"), settlementId = id(input?.settlementId, "settlementId");
  if (uid) id(uid, "uid");
  const user = await requireTrustedUser(transaction, firestore, uid, companyId);
  if (user.role !== "admin") throw new HttpsError("permission-denied", "Only administrators can preflight settlements.");
  const {read, snapshots} = settlementReader(transaction, firestore);
  const book = await readSettlementBook(read, companyId, input.expectedBookId), {c, b, bookId, context} = book;
  const [sourceSnapshot] = await read([c + "/settlements/" + settlementId]), source = required(sourceSnapshot);
  eq(source.id, settlementId, "Settlement path identity"); eq(source.companyId, companyId, "Settlement company");
  const rep = id(source.salesRepId, "salesRepId");
  const [outSnapshot, inSnapshot, legacySnapshot] = await read([
    c + "/cash_movements/" + settlementId + "_rep_out", c + "/cash_movements/" + settlementId + "_company_in",
    c + "/financial_ledger_entries/settlement_" + settlementId + "_transfer",
  ]);
  const out = required(outSnapshot), incoming = required(inSnapshot);
  eq(out.id, outSnapshot.id, "OUT document identity"); eq(incoming.id, inSnapshot.id, "IN document identity");
  if ([source, out, incoming].some(d => d.currency === undefined)) need(context.legacyCurrencyBindingRevisionId !== null,
    "Legacy source currency is blocked until its binding is approved.");
  const {mappings} = await readSettlementMappings(read, book, rep);
  const evidence: SettlementJournalIntentInput = {companyId, bookId, policy: book.policy, mappings,
    settlement: source, movements: [out, incoming]};
  const intent = validateSettlementJournalIntent(buildSettlementJournalIntent(evidence), evidence);
  const sourceCommittedAt = time(sourceSnapshot.createTime);
  for (const snapshot of [sourceSnapshot, outSnapshot, inSnapshot, legacySnapshot]) eq(compare(time(snapshot.createTime), sourceCommittedAt), 0, "Atomic source commit metadata");
  need(compare(intent.source.provenance.postedAt, sourceCommittedAt) <= 0, "Source recorded time exceeds its commit time.");
  need(compare(sourceCommittedAt, time(book.companySnapshot.readTime)) <= 0, "Source commit exceeds transaction read time.");
  const accountingDate = intent.source.settlementDate;
  periodContains(context, accountingDate); validateLegacy(required(legacySnapshot), intent);
  const {positions} = await readSettlementPositions(read, book, rep);
  for (const position of positions) need(compare(position.headCommittedAt, sourceCommittedAt) >= 0, "Cash head predates settlement.");
  const {policyRevisionId, mappingRevisionId, legacyCurrencyBindingRevisionId, period} = context;
  const preflightDigest = createHash("sha256").update(JSON.stringify([
    1, intent.id, intent.payloadDigest, sourceCommittedAt.seconds, sourceCommittedAt.nanoseconds,
    context.bookRevisionId, policyRevisionId, mappingRevisionId, legacyCurrencyBindingRevisionId,
    period.id, period.revisionId, period.startsAt.seconds, period.startsAt.nanoseconds, period.endsAt.seconds, period.endsAt.nanoseconds,
  ])).digest("hex");
  if (input.expectedPreflightDigest !== undefined) {
    need(typeof input.expectedPreflightDigest === "string" && /^[a-f0-9]{64}$/.test(input.expectedPreflightDigest), "Invalid expected preflight digest.");
    eq(input.expectedPreflightDigest, preflightDigest, "Conflicting preflight retry", "already-exists");
  }
  const keyPath = b + "/source_keys/" + intent.id, [keySnapshot] = await read([keyPath]);
  if (keySnapshot.exists) {
    const key = required(keySnapshot);
    for (const [field, expected] of Object.entries({schemaVersion: 1, companyId, bookId, sourceCollection: "settlements",
      sourceId: settlementId, action: intent.action, intentId: intent.id, payloadDigest: intent.payloadDigest, preflightDigest})) {
      eq(key[field], expected, "Conflicting source binding " + field, "already-exists");
    }
  }
  return freeze({schemaVersion: 1, mode: "committed_settlement_read_only", preparedByUid: user.uid, intent, preflightDigest, context, positions,
    sourceKey: {path: keyPath, state: keySnapshot.exists ? "matching_binding" : "absent"},
    timestamps: {accountingDate, sourceRecordedAt: intent.source.provenance.postedAt, sourceCommittedAt,
      transactionReadTime: time(book.companySnapshot.readTime), journalCommittedAt: null},
    observations: [...snapshots.values()].map(s => ({path: s.ref.path, readTime: time(s.readTime), updateTime: s.updateTime ? time(s.updateTime) : null})),
  });
}

function validateLegacy(row: DocumentData, intent: SettlementJournalIntent): void {
  const source = intent.source;
  for (const [field, expected] of Object.entries({id: `settlement_${source.id}_transfer`, companyId: intent.companyId,
    type: "settlement", component: intent.action, operationId: source.id,
    sourceCollection: "settlements", sourceId: source.id, sourcePath: source.path,
    referenceType: "settlement", referenceId: source.id, referenceNumber: source.number,
    debitAccountType: "cash", debitAccountKey: companyCashAccount().key, debitAccountId: "",
    creditAccountType: "cash", creditAccountKey: repCashAccount(source.salesRepId, "").key, creditAccountId: source.salesRepId})) {
    eq(row[field], expected, `Legacy settlement projection ${field}`);
  }
  eq(money(row.amount).toString(), intent.amountUnits, "Legacy settlement projection amount");
  if (row.currency !== undefined) eq(row.currency, intent.currency, "Legacy settlement projection currency");
  if (row.moneyScale !== undefined) eq(row.moneyScale, intent.moneyScale, "Legacy settlement projection scale");
  eq(compare(time(row.occurredAt), source.settlementDate), 0, "Legacy business date");
  // The legacy row aliases postedAt to business time, NOT actual commit time.
  eq(compare(time(row.postedAt), source.settlementDate), 0, "Legacy postedAt alias");
}

export {validateLegacy as validateSettlementLegacyProjection};
