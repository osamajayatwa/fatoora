import {Firestore, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {createHash} from "node:crypto";
import {requireTrustedUser, requiredIdempotencyKey, roundMoney} from "./common";
import {decimalNumber, sumUnits} from "./exact_decimal";
import {buildSettlementJournalEconomics, SettlementJournalEconomics} from "./settlement_journal_intent";
import {Context, Position, Time, settlementReader, readSettlementBook, readSettlementMappings,
  readSettlementPositions, periodContains, id, time, compare, money, need, eq, required, freeze} from "./settlement_preflight_shared";

export interface PendingSettlementRequest {
  companyId: string; idempotencyKey: string; salesRepId: string;
  amount: string | number; settlementDate: Time; notes?: string; expectedBookId?: string;
}
interface Version {path: string; updateTime: Time | null}
export interface PendingSettlementEvidence {
  schemaVersion: 1;
  mode: "pending_settlement";
  id: string;
  source: {
    collection: "settlements"; id: string; path: string; operationId: string;
    status: "pending"; number: string; idempotencyKey: string; notes: string;
    salesRepId: string; salesRepName: string;
    actor: {uid: string; name: string; role: "admin"};
    settlementMetadataVersion: 1; postingSource: "recordCashSettlement"; paymentMethod: "cash";
    sellerId: ""; sellerName: ""; collectorUid: ""; collectorName: "";
    sellerIdentityStatus: "not_applicable"; collectorIdentityStatus: "not_applicable";
  };
  economics: SettlementJournalEconomics;
  context: Context;
  positions: readonly (Position & {balanceCommittedAt: Time})[];
  cashEffects: readonly {
    id: string; path: string; direction: "in" | "out"; cashAccount: "company_cash" | "rep_cash";
    treasuryAccountId: string; holderType: "company" | "representative"; holderUid: string;
    counterpartMovementId: string; amountUnits: string; balanceBeforeUnits: string; balanceAfterUnits: string;
  }[];
  targets: {settlement: string; repMovement: string; companyMovement: string; legacyLedger: string;
    sourceKey: string; journal: string; event: string};
  versions: readonly Version[];
  timestamps: {
    accountingDate: Time;
    sourceRecordedAt: null; sourceCommittedAt: null;
    journalRecordedAt: null; journalCommittedAt: null;
  };
  timestampContract: {
    recordedFields: "server_transform_in_future_atomic_write";
    actualCommitMetadata: "trusted_sdk_metadata_only_after_commit";
    recordedEqualsCommit: false;
  };
  requestDigest: string; economicDigest: string; configurationDigest: string; preflightDigest: string;
}
export interface PendingSettlementPreparation {
  evidence: PendingSettlementEvidence;
  observation: {
    preparedByUid: string; transactionReadTime: Time;
    documents: readonly (Version & {readTime: Time})[];
  };
}

/** Internal read-only API. A returned value is neither approval nor reservation. */
export async function pendingSettlementEvidenceTransaction(
  firestore: Firestore, uid: string | undefined, input: PendingSettlementRequest, expectedEvidence?: unknown,
): Promise<PendingSettlementPreparation> {
  const expected = expectedEvidence === undefined ? undefined : JSON.parse(canonical(expectedEvidence));
  // Pin the request across SDK callback retries without altering its validation.
  const request = {...input, settlementDate: input?.settlementDate == null ? input?.settlementDate :
    {seconds: input.settlementDate.seconds, nanoseconds: input.settlementDate.nanoseconds}};
  return firestore.runTransaction(t => preparePendingSettlementEvidence(t, firestore, uid, request, expected));
}

/** Rebuild in every attempt, before any future caller-owned writes. No writes here. */
export async function preparePendingSettlementEvidence(
  transaction: Transaction, firestore: Firestore, uid: string | undefined,
  input: PendingSettlementRequest, expectedEvidence?: unknown,
): Promise<PendingSettlementPreparation> {
  // Snapshot caller-supplied evidence before any await; it is data, never authority.
  const expectedCanonical = expectedEvidence === undefined ? undefined : canonical(expectedEvidence);
  const prior = expectedCanonical === undefined ? undefined : JSON.parse(expectedCanonical) as Partial<PendingSettlementEvidence> | null;
  const companyId = requestId(input?.companyId, "companyId");
  if (uid) requestId(uid, "uid");
  const user = await requireTrustedUser(transaction, firestore, uid, companyId);
  if (user.role !== "admin") throw new HttpsError("permission-denied", "Only administrators can prepare settlement evidence.");
  const allowed = ["companyId", "idempotencyKey", "salesRepId", "amount", "settlementDate", "notes", "expectedBookId"];
  invalid(Object.keys(input).every(k => allowed.includes(k)), "Unexpected pending settlement request fields.");
  const key = requiredIdempotencyKey(input.idempotencyKey), rep = requestId(input.salesRepId, "salesRepId");
  invalid(user.uid !== rep, "Posting admin cannot be the representative holder.");
  let amount: bigint, date: Time;
  try {amount = money(input.amount);date = time(input.settlementDate);} catch {throw new HttpsError("invalid-argument", "Exact scale-3 amount and resolved business timestamp required.");}
  invalid(amount > 0n, "Settlement amount must be positive.");const numericAmount = decimalNumber(amount);
  invalid(input.notes === undefined || typeof input.notes === "string" && input.notes.length <= 2048, "Bounded settlement notes required.");
  const notes = input.notes?.trim() ?? "";
  if (input.expectedBookId !== undefined) requestId(input.expectedBookId, "expectedBookId");
  const {read, snapshots} = settlementReader(transaction, firestore);
  const book = await readSettlementBook(read, companyId, input.expectedBookId), {c, b, bookId, context} = book;
  periodContains(context, date);
  const {mappings, representative} = await readSettlementMappings(read, book, rep);
  // Preserve SDK version evidence for current authorization as well as its resolver checks.
  const [adminSnapshot] = await read([`users/${user.uid}`]), admin = required(adminSnapshot);
  if (admin.uid !== undefined) eq(admin.uid, user.uid, "Admin profile path identity");
  const configVersions = versions(snapshots);
  const {positions, legacyCurrency} = await readSettlementPositions(read, book, rep);
  need(!legacyCurrency || context.legacyCurrencyBindingRevisionId !== null, "Pending cash currency requires an approved legacy binding.");
  const before = positions.map(p => BigInt(p.amountUnits));
  const after = [sumUnits([before[0], -amount]), sumUnits([before[1], amount])];
  need(after.every(a => a >= 0n), "Settlement exceeds available representative cash.");
  // This pending contract must fit the unchanged legacy numeric cash writer too.
  for (const value of [...before, ...after]) decimalNumber(value);
  const legacyAfter = [roundMoney(decimalNumber(before[0]) - numericAmount), roundMoney(decimalNumber(before[1]) + numericAmount)];
  for (const [i, value] of legacyAfter.entries()) eq(value, decimalNumber(after[i]), "Exact/legacy cash arithmetic compatibility");
  const settlementId = `settlement_${key}`;
  const economics = buildSettlementJournalEconomics({companyId, bookId, settlementId, salesRepId: rep,
    amountUnits: amount.toString(), policy: book.policy, mappings});
  const targets = {settlement: `${c}/settlements/${settlementId}`, repMovement: `${c}/cash_movements/${settlementId}_rep_out`,
    companyMovement: `${c}/cash_movements/${settlementId}_company_in`, legacyLedger: `${c}/financial_ledger_entries/settlement_${settlementId}_transfer`,
    sourceKey: `${b}/source_keys/${economics.id}`, journal: `${b}/journal_entries/${economics.id}`, event: `${b}/events/${economics.id}`};
  for (const snapshot of await read(Object.values(targets))) {
    if (snapshot.exists) throw new HttpsError("already-exists", "Pending source or accounting target already exists; no posted-result claim is supported.");
  }
  const observed = [...snapshots.values()].map(s => ({path: s.ref.path, readTime: time(s.readTime), updateTime: s.updateTime ? time(s.updateTime) : null}));
  for (const observation of observed) {
    if (observation.updateTime) need(compare(observation.updateTime, observation.readTime) <= 0, "Document version exceeds its SDK read time.");
  }
  const source: PendingSettlementEvidence["source"] = {
    collection: "settlements", id: settlementId, path: targets.settlement, operationId: settlementId, status: "pending",
    // Legacy display numbering is UTC; it does not choose an accounting period.
    number: `SET-${new Date(date.seconds * 1000).toISOString().slice(0, 10).replace(/-/g, "")}-${key.slice(0, 6).toUpperCase()}`,
    idempotencyKey: key, notes, salesRepId: rep, salesRepName: textName(representative.name) || rep,
    actor: {uid: user.uid, name: user.name, role: "admin"}, settlementMetadataVersion: 1,
    postingSource: "recordCashSettlement", paymentMethod: "cash", sellerId: "", sellerName: "", collectorUid: "", collectorName: "",
    sellerIdentityStatus: "not_applicable", collectorIdentityStatus: "not_applicable",
  };
  const cashEffects: PendingSettlementEvidence["cashEffects"] = positions.map((p, i) => ({
    id: `${settlementId}_${i === 0 ? "rep_out" : "company_in"}`, path: i === 0 ? targets.repMovement : targets.companyMovement,
    direction: i === 0 ? "out" : "in", cashAccount: i === 0 ? "rep_cash" : "company_cash",
    treasuryAccountId: i === 0 ? `rep_${rep}` : "company_cash", holderType: i === 0 ? "representative" : "company",
    holderUid: i === 0 ? rep : companyId, counterpartMovementId: `${settlementId}_${i === 0 ? "company_in" : "rep_out"}`,
    amountUnits: amount.toString(), balanceBeforeUnits: p.amountUnits, balanceAfterUnits: after[i].toString(),
  }));
  eq(sumUnits(before), sumUnits(after), "Total company cash conservation");
  const requestDigest = digest({schemaVersion: 1, companyId, settlementId, salesRepId: rep,
    amountUnits: amount.toString(), accountingDate: date, notes, initiatedByUid: user.uid});
  const economicDigest = digest({schemaVersion: 1, source, economics, accountingDate: date});
  const configurationDigest = digest({schemaVersion: 1, context, policy: economics.policy,
    accounts: economics.lines.map(l => l.account), versions: configVersions});
  const snapshotVersions = versions(snapshots);
  const cashPositions = positions.map(p => ({...p, balanceCommittedAt: time(snapshots.get(p.path)!.updateTime)}));
  const preflightDigest = digest({schemaVersion: 1, mode: "pending_settlement", economicDigest, configurationDigest,
    positions: cashPositions, cashEffects, versions: snapshotVersions, targets});
  const evidence: PendingSettlementEvidence = {schemaVersion: 1, mode: "pending_settlement", id: economics.id,
    source, economics, context, positions: cashPositions, cashEffects, targets, versions: snapshotVersions,
    timestamps: {accountingDate: date, sourceRecordedAt: null, sourceCommittedAt: null, journalRecordedAt: null, journalCommittedAt: null},
    timestampContract: {recordedFields: "server_transform_in_future_atomic_write",
      actualCommitMetadata: "trusted_sdk_metadata_only_after_commit", recordedEqualsCommit: false},
    requestDigest, economicDigest, configurationDigest, preflightDigest};
  if (prior !== undefined) {
    invalid(prior !== null && typeof prior === "object" && prior.schemaVersion === 1 && prior.mode === "pending_settlement", "Pending evidence schema/mode mismatch.");
    if (prior.requestDigest !== requestDigest) throw new HttpsError("already-exists", "Conflicting pending settlement request.");
    if (prior.configurationDigest !== configurationDigest || prior.preflightDigest !== preflightDigest) throw new HttpsError("failed-precondition", "Stale pending settlement evidence; prepare and review again.");
    invalid(expectedCanonical === canonical(evidence), "Pending evidence does not match freshly validated source/configuration.");
  }
  return freeze({evidence, observation: {preparedByUid: user.uid, transactionReadTime: time(book.companySnapshot.readTime), documents: observed}});
}

function versions(snapshots: Map<string, import("firebase-admin/firestore").DocumentSnapshot>): Version[] {
  return [...snapshots.values()].map(s => ({path: s.ref.path, updateTime: s.updateTime ? time(s.updateTime) : null}))
    .sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
}
function invalid(condition: boolean, message: string): asserts condition {if (!condition) throw new HttpsError("invalid-argument", message);}
function requestId(value: unknown, label: string): string {try {return id(value, label);} catch {throw new HttpsError("invalid-argument", `${label} must be a bounded single identifier.`);}}
function textName(value: unknown): string {return typeof value === "string" ? value.trim() : "";}
function canonical(value: unknown): string {
  let nodes = 0;
  const normalize = (v: unknown, depth: number): unknown => {
    invalid(++nodes <= 4096 && depth <= 16, "Pending evidence exceeds structural limits.");
    if (v === null || typeof v === "boolean") return v;
    if (typeof v === "string") {invalid(v.length <= 2048, "Pending evidence string too long.");return v;}
    if (typeof v === "number") {invalid(Number.isSafeInteger(v), "Pending evidence number must be a safe integer.");return v;}
    invalid(typeof v === "object", "Pending evidence must contain JSON data only.");
    if (Array.isArray(v)) {
      invalid(v.length <= 64 && Reflect.ownKeys(v).length === v.length + 1, "Pending evidence arrays must be bounded and dense.");
      const descriptors = Object.getOwnPropertyDescriptors(v);
      return Array.from({length: v.length}, (_, i) => {
        const d = descriptors[i];
        invalid(d !== undefined && "value" in d, "Pending evidence arrays must contain data at every index.");
        return normalize(d.value, depth + 1);
      });
    }
    invalid(Object.getPrototypeOf(v) === Object.prototype || Object.getPrototypeOf(v) === null, "Pending evidence must be plain JSON.");
    const keys = Object.keys(v);
    invalid(keys.length <= 64 && Reflect.ownKeys(v).length === keys.length, "Unexpected pending evidence properties.");
    keys.sort();const descriptors = Object.getOwnPropertyDescriptors(v);
    return Object.fromEntries(keys.map(k => {invalid(k.length <= 128 && "value" in descriptors[k], "Invalid pending evidence property.");return [k, normalize(descriptors[k].value, depth + 1)];}));
  };
  const encoded = JSON.stringify(normalize(value, 0));invalid(Buffer.byteLength(encoded, "utf8") <= 65536, "Pending evidence exceeds 64 KiB.");return encoded;
}
function digest(value: unknown): string {return createHash("sha256").update(canonical(value)).digest("hex");}
