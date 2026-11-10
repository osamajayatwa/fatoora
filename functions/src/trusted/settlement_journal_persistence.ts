import {DocumentData, DocumentReference, DocumentSnapshot, FieldValue, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {requireTrustedUser} from "./common";
import {decimalNumber, formatUnits, sumUnits} from "./exact_decimal";
import {prepareCashSettlementWrite} from "./record_cash_settlement";
import {buildSettlementJournalIntent, settlementJournalIdentity} from "./settlement_journal_intent";
import {validateSettlementLegacyProjection} from "./settlement_preflight";
import {buildSettlementFinancialLedgerEntry} from "./financial_ledger_mappings";
import {PendingSettlementEvidence, PendingSettlementRequest, preparePendingSettlementEvidence,
  normalizePendingSettlementRequest, canonicalSettlementEvidence as canonical, settlementEvidenceDigest as digest} from "./settlement_pending_evidence";
import {Time, compare, eq, freeze, id, money, need, required, time} from "./settlement_preflight_shared";
import {SettlementReadTarget, assertApprovedSettlementReadTarget, assertSettlementReadTransaction} from "./settlement_read_target";

export interface SettlementJournalOptions {enableEmulatorPersistence?: boolean}
export interface SettlementJournalResult {
  schemaVersion: 1; companyId: string; bookId: string; settlementId: string;
  journalId: string; eventId: string; requestId: string; sourceKeyPath: string;
  requestDigest: string; economicDigest: string; preflightDigest: string;
  laneId: string; laneSequence: number;
}
interface CommitEvidence {committedAt: Time; sourceRecordedAt: Time; journalRecordedAt: Time}
type Decision = {state: "staged"; result: SettlementJournalResult} |
  {state: "committed"; result: SettlementJournalResult; commit: CommitEvidence};
type Links = PendingSettlementEvidence["targets"] & {request: string; audit: string; outbox: string; postingContract: string; lane: string};
const GENESIS = "0".repeat(64);

/** Never a callable/root export. Both explicit opt-in and a synthetic loopback
 * database are mandatory. No live posting flag is enabled by this module. */
export async function persistSettlementJournalTransaction(
  firestore: Firestore, uid: string | undefined, input: PendingSettlementRequest,
  expectedEvidence?: unknown, options: SettlementJournalOptions = {},
): Promise<{result: SettlementJournalResult; recovered: boolean; commit: CommitEvidence}> {
  isolated(firestore, options);
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  const n = normalizePendingSettlementRequest(input, uid);
  persistableDate(n.date);
  const request: PendingSettlementRequest = freeze({companyId: n.companyId, idempotencyKey: n.key, salesRepId: n.rep,
    amount: formatUnits(BigInt(n.amountUnits), 3), settlementDate: n.date, notes: n.notes,
    ...(n.expectedBookId === undefined ? {} : {expectedBookId: n.expectedBookId})});
  const expected = expectedEvidence === undefined ? undefined : JSON.parse(canonical(expectedEvidence));
  const first = await firestore.runTransaction(t => prepare(t, firestore, uid, request, expected, options, false));
  if (first.state === "committed") return freeze({result: first.result, recovered: true, commit: first.commit});
  // runTransaction returns no WriteResult. Observe real SDK metadata after the
  // atomic commit; a failed/lost acknowledgement is recovered by the same key.
  const observed = await firestore.runTransaction(t => prepare(t, firestore, uid, request, expected, options, true));
  need(observed.state === "committed", "Committed settlement observation is unavailable.");
  return freeze({result: observed.result, recovered: false, commit: observed.commit});
}

/** Caller-owned composition seam, subject to the same emulator/default-off
 * restrictions. A staged decision is NOT a committed result or timestamp. */
export async function prepareSettlementJournalPersistence(
  transaction: Transaction, firestore: Firestore, uid: string | undefined, input: PendingSettlementRequest,
  expectedEvidence?: unknown, options: SettlementJournalOptions = {},
): Promise<Decision> {return prepare(transaction, firestore, uid, input, expectedEvidence, options, false);}

/** Recovery-only seam. A missing source can never enter the posting branch.
 * The independent verifier supplies a transaction that rejects every write. */
export async function prepareCommittedSettlementRecovery(
  transaction: Transaction, firestore: Firestore, uid: string | undefined, input: PendingSettlementRequest,
  expectedEvidence?: unknown, readTarget?: SettlementReadTarget,
) {
  const options = {enableEmulatorPersistence: true};
  if (readTarget) assertApprovedSettlementReadTarget(firestore, readTarget, input?.companyId);else isolated(firestore, options);
  const transactionDb = Reflect.get(transaction, "_firestore");
  need(transactionDb && typeof transactionDb === "object", "A supported isolated SDK transaction is required.");
  if (readTarget) assertSettlementReadTransaction(transaction, firestore, readTarget);else isolated(transactionDb, options);
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  const companyId = id(input?.companyId, "companyId"), key = normalizePendingSettlementRequest(input, uid).key;
  const expected = expectedEvidence === undefined ? undefined : JSON.parse(canonical(expectedEvidence));
  const tx = cachedTransaction(transaction), user = await requireTrustedUser(tx, firestore, uid, companyId);
  if (user.role !== "admin") throw new HttpsError("permission-denied", "Only administrators can verify settlement accounting.");
  const viewer = required(await tx.get(firestore.doc(`users/${uid}`)));
  if (viewer.uid !== undefined) eq(viewer.uid, uid, "Viewer profile path identity");
  const [company, source] = await tx.getAll(firestore.doc(`companies/${companyId}`), firestore.doc(`companies/${companyId}/settlements/settlement_${key}`));
  eq(required(company).id, companyId, "Company identity");eq(required(company).active, true, "Active company");
  if (required(company).companyId !== undefined) eq(required(company).companyId, companyId, "Company scope metadata");
  if (!source.exists) corrupt("Committed source is missing; recovery never posts another settlement.");
  // Viewing authority belongs to today's administrator; durable request identity
  // belongs to the original posting actor, even if that actor is now inactive.
  const n = normalizePendingSettlementRequest(input, id(required(source).createdByUid, "Original posting actor"));
  persistableDate(n.date);
  const decision = await recover(tx, firestore, n, source, expected, company);
  need(decision.state === "committed", "Committed settlement required.");
  return {result: decision.result, recovered: true as const, commit: decision.commit};
}

async function prepare(
  transaction: Transaction, firestore: Firestore, uid: string | undefined, input: PendingSettlementRequest,
  expectedEvidence: unknown, options: SettlementJournalOptions, recoveryOnly: boolean,
): Promise<Decision> {
  isolated(firestore, options);
  const transactionDb = Reflect.get(transaction, "_firestore");
  need(transactionDb && typeof transactionDb === "object", "A supported isolated SDK transaction is required.");
  isolated(transactionDb, options);
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  const n = normalizePendingSettlementRequest(input, uid);
  persistableDate(n.date);
  const expected = expectedEvidence === undefined ? undefined : JSON.parse(canonical(expectedEvidence));
  const tx = cachedTransaction(transaction), user = await requireTrustedUser(tx, firestore, uid, n.companyId);
  if (user.role !== "admin") throw new HttpsError("permission-denied", "Only administrators can post settlement accounting.");
  const companyPath = `companies/${n.companyId}`, sourcePath = `${companyPath}/settlements/settlement_${n.key}`;
  const [companySnapshot, source] = await tx.getAll(firestore.doc(companyPath), firestore.doc(sourcePath));
  const company = required(companySnapshot);eq(company.id, n.companyId, "Company identity");eq(company.active, true, "Active company");
  if (source.exists) return recover(tx, firestore, n, source, expected, companySnapshot);
  if (recoveryOnly) corrupt("Committed source is missing; recovery never posts another settlement.");
  if (expected === undefined) throw new HttpsError("invalid-argument", "Reviewed pending settlement evidence is required.");
  const {evidence: e} = await preparePendingSettlementEvidence(tx, firestore, uid, input, expected);
  const b = `${companyPath}/books/${e.economics.bookId}`, book = required(await tx.get(firestore.doc(b)));
  eq(book.settlementJournalEmulatorEnabled, true, "Default-off emulator persistence gate");
  const definitionId = id(book.settlementJournalDefinitionId, "settlementJournalDefinitionId");
  const definitionRevision = id(book.settlementJournalDefinitionRevisionId, "settlementJournalDefinitionRevisionId");
  const laneCount = book.postingLaneCount;
  need(Number.isSafeInteger(laneCount) && laneCount >= 1 && laneCount <= 64, "Explicit bounded posting lane count required.");
  eq(book.postingLaneSchemaVersion, 1, "Supported posting lane schema");
  const laneId = `lane_${(parseInt(digest(e.id).slice(0, 8), 16) % laneCount).toString().padStart(2, "0")}`;
  const links = linksFor(n.companyId, e.economics.bookId, n.key, uid, laneId);
  const [definitionSnapshot, seal, lane, request, audit, outbox] = await tx.getAll(
    ...[`${b}/journal_definitions/${definitionId}`, links.postingContract, links.lane, links.request, links.audit, links.outbox].map(p => firestore.doc(p)));
  const definitionData = required(definitionSnapshot);
  immutable(definitionSnapshot);
  need(compare(time(definitionSnapshot.createTime), time((await tx.get(firestore.doc(b))).updateTime)) <= 0,
    "Journal definition must exist when its approved book revision is pinned.");
  for (const [field, value] of Object.entries({id: definitionId, companyId: n.companyId, bookId: e.economics.bookId,
    revisionId: definitionRevision, approvalStatus: "approved", active: true, action: "rep_to_company_cash",
    currency: e.economics.currency, moneyScale: 3, numberingPolicy: "source_identity"})) eq(definitionData[field], value, `Journal definition ${field}`);
  const definition = {id: definitionId, revisionId: definitionRevision, snapshotVersion: time(definitionSnapshot.updateTime),
    numberingPolicy: "source_identity"};
  const contract = {schemaVersion: 1, companyId: n.companyId, bookId: e.economics.bookId, currency: e.economics.currency,
    moneyScale: 3, postingLaneCount: laneCount, postingLaneSchemaVersion: 1, journalEntrySchemaVersion: 1};
  const contractDigest = digest(contract), contractBinding = {schemaVersion: 1, path: links.postingContract, digest: contractDigest};
  if (seal.exists) {
    same(readRecord(seal), contract, "Pinned book monetary/lane contract");
    same(book.settlementPostingContract, contractBinding, "Initialized book contract binding");
  } else {
    need(book.settlementPostingContract === undefined && !lane.exists, "An initialized book cannot lose its immutable posting contract.");
  }
  for (const target of [request, audit, outbox]) if (target.exists) throw new HttpsError("already-exists", "Accounting target collision.");
  let sequence = 1, previousEventId: string | null = null, previousEventHash = GENESIS;
  if (lane.exists) {
    const head = required(lane);
    for (const [field, value] of Object.entries({schemaVersion: 1, id: laneId, companyId: n.companyId, bookId: e.economics.bookId,
      currency: e.economics.currency, moneyScale: 3, contractDigest})) eq(head[field], value, `Lane ${field}`);
    need(Number.isSafeInteger(head.sequence) && head.sequence > 0 && head.sequence < Number.MAX_SAFE_INTEGER, "Valid lane sequence required.");
    previousEventId = id(head.lastEventId, "lastEventId");previousEventHash = hashValue(head.lastEventHash);
    const previous = await tx.get(firestore.doc(`${b}/events/${previousEventId}`)), payload = readRecord(previous);
    eq(payload.eventId, previousEventId, "Lane head event");eq(payload.bookId, e.economics.bookId, "Lane head book");
    eq(payload.companyId, n.companyId, "Lane head company");eq(payload.contractDigest, contractDigest, "Lane head contract");
    eq(payload.lane.id, laneId, "Lane head identity");eq(payload.lane.sequence, head.sequence, "Lane head sequence");
    eq(eventHash(payload), previousEventHash, "Lane head hash");
    eq(compare(time(lane.updateTime), time(previous.createTime)), 0, "Atomic lane/head metadata");
    need(compare(time(seal.createTime), time(previous.createTime)) <= 0, "Book posting contract was recreated after its lane history.");
    sequence = head.sequence + 1;
  }
  const artifacts = buildArtifacts(e, links, definition, contract, {id: laneId, sequence, previousEventId, previousEventHash});
  // Reuse all original settlement reads, cash arithmetic, metadata, ledger and
  // balance writes. This is the only cash-posting implementation.
  const cash = await prepareCashSettlementWrite(tx, firestore, uid, n.companyId, n.key,
    {salesRepId: n.rep, amount: decimalNumber(BigInt(n.amountUnits)), settlementDate: new Timestamp(n.date.seconds, n.date.nanoseconds), notes: n.notes});
  need(!cash.alreadyPosted, "New accounting posting requires an unposted settlement.");
  // No reads below this line. Every immutable artifact uses create preconditions.
  cash.write({immutableCreate: true, accountingBinding: artifacts.binding});
  for (const [path, payload] of artifacts.records) tx.create(firestore.doc(path), record(payload));
  if (!seal.exists) {
    tx.create(firestore.doc(links.postingContract), record(contract));
    // Initialize once, never a per-post book counter. The independent binding
    // blocks a missing seal even when the next event selects an empty lane.
    tx.update(firestore.doc(b), {settlementPostingContract: contractBinding});
  }
  const nextLane = {schemaVersion: 1, id: laneId, companyId: n.companyId, bookId: e.economics.bookId,
    currency: e.economics.currency, moneyScale: 3, contractDigest, sequence, lastEventId: e.id,
    lastEventHash: artifacts.event.eventHash, updatedAt: FieldValue.serverTimestamp()};
  if (lane.exists) tx.update(firestore.doc(links.lane), nextLane);else tx.create(firestore.doc(links.lane), nextLane);
  return {state: "staged", result: artifacts.result};
}

function buildArtifacts(e: PendingSettlementEvidence, links: Links, definition: DocumentData, contract: DocumentData,
  lane: {id: string; sequence: number; previousEventId: string | null; previousEventHash: string}) {
  const result: SettlementJournalResult = {schemaVersion: 1, companyId: e.economics.companyId, bookId: e.economics.bookId,
    settlementId: e.source.id, journalId: e.id, eventId: e.id, requestId: links.request.slice(links.request.lastIndexOf("/") + 1),
    sourceKeyPath: links.sourceKey, requestDigest: e.requestDigest, economicDigest: e.economicDigest,
    preflightDigest: e.preflightDigest, laneId: lane.id, laneSequence: lane.sequence};
  const binding = {schemaVersion: 1, companyId: result.companyId, bookId: result.bookId, sourceId: e.source.id,
    sourceCollection: "settlements", action: "rep_to_company_cash", journalId: e.id, eventId: e.id, requestId: result.requestId,
    currency: e.economics.currency, moneyScale: 3, requestDigest: e.requestDigest, economicDigest: e.economicDigest,
    preflightDigest: e.preflightDigest, links, laneId: lane.id, laneSequence: lane.sequence};
  const debitUnits = sumUnits(e.economics.lines.map(l => BigInt(l.debitUnits))).toString();
  const creditUnits = sumUnits(e.economics.lines.map(l => BigInt(l.creditUnits))).toString();
  eq(debitUnits, creditUnits, "Journal balance");eq(debitUnits, e.economics.amountUnits, "Journal settlement amount");
  const reconciliationBase = {sourcePath: links.settlement, legacyLedgerPath: links.legacyLedger,
    cashMovementPaths: [links.repMovement, links.companyMovement], cashPositionPaths: e.positions.map(p => p.path),
    journalPath: links.journal, currency: e.economics.currency, moneyScale: 3, debitUnits, creditUnits,
    totalCashBeforeUnits: sumUnits(e.cashEffects.map(p => BigInt(p.balanceBeforeUnits))).toString(),
    totalCashAfterUnits: sumUnits(e.cashEffects.map(p => BigInt(p.balanceAfterUnits))).toString(), cashEffects: e.cashEffects};
  eq(reconciliationBase.totalCashBeforeUnits, reconciliationBase.totalCashAfterUnits, "Cash conservation");
  const reconciliation = {...reconciliationBase, effectDigest: digest(reconciliationBase)};
  const journal = {...binding, id: e.id, status: "posted", amountUnits: e.economics.amountUnits, debitUnits, creditUnits,
    lines: e.economics.lines, accountingDate: e.timestamps.accountingDate, periodId: e.context.period.id, context: e.context,
    journalDefinitionId: definition.id, journalDefinitionRevisionId: definition.revisionId, reversalOf: null};
  const baseEvent = {...binding, id: e.id, kind: "settlement_posted", accountingDate: e.timestamps.accountingDate,
    pendingEvidence: e, definition, contract, contractDigest: digest(contract), journalDigest: digest(journal), reconciliation, lane};
  const event = {...baseEvent, eventHash: digest(baseEvent)};
  const shared = {...binding, eventHash: event.eventHash, journalDigest: digest(journal)};
  const records: [string, DocumentData][] = [[links.journal, journal], [links.event, event],
    [links.sourceKey, {...shared, kind: "source_binding"}],
    [links.request, {...shared, kind: "request_result", actorUid: e.source.actor.uid, requestKey: e.source.idempotencyKey, result}],
    [links.audit, {...shared, kind: "settlement_accounting_posted", actor: e.source.actor}],
    [links.outbox, {...shared, kind: "accounting_projection_intent", projectionIntent: "reconcile_settlement", effectDigest: reconciliation.effectDigest}]];
  return {result, binding, event, records};
}

async function recover(tx: Transaction, db: Firestore, n: ReturnType<typeof normalizePendingSettlementRequest>,
  source: DocumentSnapshot, expected: unknown, company: DocumentSnapshot): Promise<Decision> {
  const data = required(source), bound = data.accounting;
  if (!bound || typeof bound !== "object") throw new HttpsError("already-exists", "Legacy settlement has no atomic journal binding; backfill is forbidden.");
  const bookId = id(bound.bookId, "Committed book"), entryId = settlementJournalIdentity(n.companyId, bookId, `settlement_${n.key}`);
  if (bound.requestDigest !== n.requestDigest) throw new HttpsError("already-exists", "Conflicting committed settlement request.");
  if (n.expectedBookId !== undefined) eq(n.expectedBookId, bookId, "Committed book constraint", "already-exists");
  const laneId = id(bound.laneId, "Committed lane"), links = linksFor(n.companyId, bookId, n.key, data.createdByUid, laneId);
  const keys = ["settlement", "repMovement", "companyMovement", "legacyLedger", "journal", "event", "sourceKey", "request", "audit", "outbox"] as const;
  const snapshots = await tx.getAll(...keys.map(k => db.doc(links[k]))), map = new Map(snapshots.map(s => [s.ref.path, s]));
  const commitAt = time(source.createTime);
  for (const s of snapshots) {immutable(s);eq(compare(time(s.createTime), commitAt), 0, "Atomic committed artifact metadata");}
  need(compare(commitAt, time(company.readTime)) <= 0, "Committed source exceeds SDK observation time.");
  const event = readRecord(map.get(links.event)!), e = event.pendingEvidence as PendingSettlementEvidence;
  same(e?.requestDigest, n.requestDigest, "Committed request binding");same(e?.id, entryId, "Committed journal identity");
  if (expected !== undefined) same(expected, e, "Original reviewed evidence", "invalid-argument");
  same(normalizePendingSettlementRequest({companyId: n.companyId, idempotencyKey: e.source.idempotencyKey,
    salesRepId: e.source.salesRepId, amount: formatUnits(BigInt(e.economics.amountUnits), 3),
    settlementDate: e.timestamps.accountingDate, notes: e.source.notes}, e.source.actor.uid).requestDigest, n.requestDigest, "Stored request identity");
  const sealSnapshot = await tx.get(db.doc(links.postingContract)), contract = readRecord(sealSnapshot);
  need(compare(time(sealSnapshot.createTime), commitAt) <= 0, "Book posting contract was recreated after this event.");
  same(contract, event.contract, "Immutable book posting contract");
  const artifacts = buildArtifacts(e, links, event.definition, contract, event.lane);
  same(bound, artifacts.binding, "Original source accounting binding");
  for (const [path, payload] of artifacts.records) same(readRecord(map.get(path)!), payload, "Committed accounting artifact");
  for (const path of [links.repMovement, links.companyMovement, links.legacyLedger]) same(required(map.get(path)!).accounting, artifacts.binding, "Original effect binding");
  const out = required(map.get(links.repMovement)!), incoming = required(map.get(links.companyMovement)!);
  const committed = buildSettlementJournalIntent({companyId: n.companyId, bookId, policy: e.economics.policy,
    mappings: e.economics.lines.map(l => l.account), settlement: data, movements: [out, incoming]});
  same(committed.lines, e.economics.lines, "Committed cash/journal dimensions");
  same(committed.source.settlementDate, n.date, "Committed business date");same(data.notes, n.notes, "Committed notes");
  same(data.salesRepId, n.rep, "Committed representative");same(committed.amountUnits, n.amountUnits, "Committed amount");
  same(data.settlementNumber, e.source.number, "Committed source number");same(data.salesRepName, e.source.salesRepName, "Committed representative name");
  same(data.createdByUid, e.source.actor.uid, "Committed initiator");same(data.postedByUid, e.source.actor.uid, "Committed posting actor");
  same(committed.source.provenance.createdBy, e.source.actor, "Committed actor snapshot");
  for (const movement of [out, incoming]) {
    same(movement.notes, e.source.notes, "Committed movement notes");same(movement.salesRepName, e.source.salesRepName, "Committed movement representative name");
  }
  same([out.balanceBefore, out.balanceAfter, incoming.balanceBefore, incoming.balanceAfter].map(v => money(v).toString()),
    [e.cashEffects[0].balanceBeforeUnits, e.cashEffects[0].balanceAfterUnits, e.cashEffects[1].balanceBeforeUnits, e.cashEffects[1].balanceAfterUnits], "Committed cash effect amounts");
  validateSettlementLegacyProjection(required(map.get(links.legacyLedger)!), committed);
  const legacyExpected = {...buildSettlementFinancialLedgerEntry({companyId: n.companyId, settlementId: e.source.id,
    settlementNumber: e.source.number, settlementDate: new Timestamp(n.date.seconds, n.date.nanoseconds),
    amount: decimalNumber(BigInt(n.amountUnits)), salesRepId: n.rep, salesRepName: e.source.salesRepName, notes: n.notes}), accounting: artifacts.binding};
  const legacy = required(map.get(links.legacyLedger)!);
  same(legacyComparable(legacy), legacyComparable(legacyExpected), "Complete legacy transfer projection");
  const sourceRecordedAt = time(data.postedAt), journalRecordedAt = time(map.get(links.journal)!.data()!.recordedAt);
  need(compare(sourceRecordedAt, commitAt) <= 0 && compare(journalRecordedAt, commitAt) <= 0, "Recorded time exceeds SDK commit metadata.");
  return {state: "committed", result: artifacts.result, commit: {committedAt: commitAt, sourceRecordedAt, journalRecordedAt}};
}

function linksFor(companyId: string, bookId: string, key: string, uid: string, laneId: string): Links {
  const c = `companies/${companyId}`, b = `${c}/books/${bookId}`, sourceId = `settlement_${key}`;
  const entryId = settlementJournalIdentity(companyId, bookId, sourceId);
  const requestId = `settlement_request_${digest([1, companyId, bookId, uid, "recordCashSettlement", key])}`;
  return {settlement: `${c}/settlements/${sourceId}`, repMovement: `${c}/cash_movements/${sourceId}_rep_out`,
    companyMovement: `${c}/cash_movements/${sourceId}_company_in`, legacyLedger: `${c}/financial_ledger_entries/settlement_${sourceId}_transfer`,
    sourceKey: `${b}/source_keys/${entryId}`, journal: `${b}/journal_entries/${entryId}`, event: `${b}/events/${entryId}`,
    request: `${b}/request_keys/${requestId}`, audit: `${b}/audit_events/${entryId}`, outbox: `${b}/outbox/${entryId}`,
    postingContract: `${b}/posting_contracts/settlement-v1`, lane: `${b}/posting_lanes/${laneId}`};
}
function record(payload: DocumentData): DocumentData {
  return {...payload, ...(payload.accountingDate ? {accountingDate: new Timestamp(payload.accountingDate.seconds, payload.accountingDate.nanoseconds)} : {}),
    recordDigest: digest(payload), recordedAt: FieldValue.serverTimestamp(), committedAt: null};
}
function readRecord(snapshot: DocumentSnapshot): DocumentData {
  immutable(snapshot);
  const {recordDigest, recordedAt, committedAt, ...payload} = required(snapshot);
  need(compare(time(recordedAt), time(snapshot.createTime)) <= 0, "Recorded timestamp exceeds SDK commit metadata.");
  same(committedAt, null, "Unknown embedded commit timestamp");
  const normalized = {...payload, ...(payload.accountingDate ? {accountingDate: time(payload.accountingDate)} : {})};
  same(digest(normalized), hashValue(recordDigest), "Immutable record digest");return normalized;
}
function immutable(snapshot: DocumentSnapshot): void {
  if (!snapshot.exists || !snapshot.createTime || !snapshot.updateTime || compare(time(snapshot.createTime), time(snapshot.updateTime)) !== 0) corrupt("Immutable posting evidence is missing or was overwritten.");
}
function same(actual: unknown, expected: unknown, label: string, code: "data-loss" | "invalid-argument" = "data-loss"): void {
  if (canonical(actual) !== canonical(expected)) throw new HttpsError(code, `${label} is inconsistent.`);
}
function hashValue(value: unknown): string {need(typeof value === "string" && /^[a-f0-9]{64}$/.test(value), "Valid immutable digest required.");return value;}
function eventHash(payload: DocumentData): string {const {eventHash: stored, ...base} = payload;const computed = digest(base);same(stored, computed, "Event hash");return computed;}
function corrupt(message: string): never {throw new HttpsError("data-loss", message);}
function persistableDate(date: Time): void {
  if (date.nanoseconds % 1000 !== 0) throw new HttpsError("invalid-argument", "Accounting timestamp must be exactly representable at Firestore microsecond precision.");
}
function legacyComparable(row: DocumentData): DocumentData {
  const normalized: DocumentData = {...row, occurredAt: time(row.occurredAt), postedAt: time(row.postedAt), amount: money(row.amount).toString()};
  // The compatibility ledger uses numeric money. Compare exact units without
  // weakening the journal evidence codec's prohibition on floating point.
  for (const key of Object.keys(row).filter(k => k.startsWith("metric"))) normalized[key] = money(row[key]).toString();
  return normalized;
}
function isolated(db: Firestore, options: SettlementJournalOptions): void {
  need(options.enableEmulatorPersistence === true, "Settlement journal persistence is disabled by default.");
  const host = process.env.FIRESTORE_EMULATOR_HOST ?? "";
  need(/^127\.0\.0\.1:\d+$/.test(host), "A dedicated loopback emulator is required.");
  // Fail closed against the resolved transport, including clients constructed
  // before the environment was set. These are the pinned SDK's runtime getters
  // and resolved settings; never initialize/discover cloud credentials here.
  const settings = Reflect.get(db, "_settings");
  let project: unknown;try {project = Reflect.get(db, "projectId");} catch {project = null;}
  need(project === "demo-fatoora-phase2b7" && db.databaseId === "(default)" &&
    settings?.servicePath === "127.0.0.1" && settings?.ssl === false && settings?.port === Number(host.split(":")[1]),
    "Settlement journal persistence is restricted to the dedicated synthetic loopback emulator.");
}

/** Shared transport guard, invoked before starting any independent read. */
export function assertSettlementRecoveryEmulator(db: Firestore): void {
  isolated(db, {enableEmulatorPersistence: true});
}

/** One-attempt read cache shared by auth, preflight and the original writer.
 * Enforce bounded document-only reads and reads-before-writes even on cache hits. */
function cachedTransaction(transaction: Transaction): Transaction {
  const cache = new Map<string, DocumentSnapshot>();let writing = false, writes = 0;
  const read = async (refs: DocumentReference[]) => {
    need(!writing, "All reads must precede settlement writes.");
    need(refs.every(ref => typeof ref?.path === "string" && typeof ref.collection === "function"), "Only document reads are supported.");
    const missing = [...new Map(refs.filter(r => !cache.has(r.path)).map(r => [r.path, r])).values()];
    need(cache.size + missing.length <= 48, "Settlement atomic read budget exceeded.");
    if (missing.length) {
      let snapshots: DocumentSnapshot[];
      try {snapshots = await transaction.getAll(...missing);} catch (error) {
        const failure = error as {code?: unknown; details?: unknown; message?: unknown};
        // Emulator 1.21 can invalidate a contending read transaction with this
        // exact INVALID_ARGUMENT rather than ABORTED. The installed SDK only
        // retries the real backend's differently worded expired-ID code 3.
        // Normalize only this read failure into its bounded SDK retry path;
        // every callback still rechecks the original expected evidence.
        if (failure.code === 3 && (failure.details === "Transaction is invalid or closed." ||
          failure.message === "3 INVALID_ARGUMENT: Transaction is invalid or closed.")) {
          throw Object.assign(new Error("Emulator invalidated the settlement read transaction.", {cause: error}), {code: 10});
        }
        throw error;
      }
      for (const s of snapshots) cache.set(s.ref.path, s);
    }
    return refs.map(r => cache.get(r.path)!);
  };
  return new Proxy(transaction, {get(target, prop) {
    if (prop === "get") return async (ref: DocumentReference) => (await read([ref]))[0];
    if (prop === "getAll") return (...refs: DocumentReference[]) => read(refs);
    if (["create", "set", "update", "delete"].includes(String(prop))) return (...args: unknown[]) => {
      writing = true;need(++writes <= 16, "Settlement atomic write budget exceeded.");
      return Reflect.apply(Reflect.get(target, prop), target, args);
    };
    const value = Reflect.get(target, prop);return typeof value === "function" ? value.bind(target) : value;
  }});
}
