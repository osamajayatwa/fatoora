import {DocumentData, DocumentSnapshot, FieldValue, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {requireTrustedUser, TrustedUser} from "./common";
import {AccountingConfiguration, accountingConfigurationReadiness, configurationDigest, configurationId, validateAccountingConfiguration} from "./accounting_configuration_contract";
import {AccountingJournal, AccountingTime, JournalAccount, accountingCanonical, accountingDigest, accountingEventId, accountingHash,
  accountingLocalDate, accountingNeed, accountingSame, accountingTime, validateAccountingJournal} from "./accounting_journal";
import {AccountingEmulatorOptions, accountingRecord, accountingTransaction, assertAccountingEmulator, immutableAccountingRecord} from "./accounting_transaction";
import {accountingDomainWitness, prepareEffectManifest, readAccountingEffects} from "./accounting_effects";
import {AccountingControlEffect, AccountingStockEffect, verifyAccountingControls} from "./accounting_controls";
import {ACCOUNTING_CONTROL_COLLECTIONS} from "./accounting_transaction";
export {accountingDomainWitness} from "./accounting_effects";

export interface AccountingCommand {
  companyId: string; bookId: string; requestId: string; expectedConfigurationDigest: string;
  source: AccountingJournal["source"]; businessTime: AccountingTime; semantic: Record<string, unknown>;
}
export interface AccountingPostingContext {
  companyId: string; bookId: string; actor: TrustedUser; configuration: AccountingConfiguration;
  configurationDigest: string; revisionId: string; accountingDate: string; periodId: string;
  definitionId: string; definitionRevisionId: string; allowedControls: string[];
  source: AccountingJournal["source"]; businessTime: AccountingTime; eventId: string;
}
export interface AccountingDomainWrite {method: "create" | "set" | "update"; path: string; data: DocumentData; merge?: boolean}
export interface AccountingPostingAdapter {
  definitionId: string; domainPaths: readonly string[];
  controlCollections?: readonly string[]; itemPaths?: readonly string[];
  prepare(tx: Transaction, db: Firestore, context: AccountingPostingContext): Promise<{
    journal: AccountingJournal | null; controlEffects?: AccountingControlEffect[]; stockEffects?: AccountingStockEffect[];
    writes(binding: DocumentData): AccountingDomainWrite[];
  }>;
}
export interface AccountingPostingResult {
  schemaVersion: 1; companyId: string; bookId: string; eventId: string; journalId: string | null;
  sourceId: string; sourceType: string; laneId: string; laneSequence: number;
  economicDigest: string; journalDigest: string | null; configurationDigest: string;
}
type Decision = {result: AccountingPostingResult; alreadyPosted: boolean};
const GENESIS = "0".repeat(64);
const ENVIRONMENT = "synthetic_emulator_only";
const immutableCollections = ["journal_entries", "events", "source_keys", "request_keys", "audit_events", "outbox", "posting_contracts", "event_effect_chunks"];
function freezeEvidence<T>(value: T): T {
  if (value && typeof value === "object") {for (const child of Object.values(value)) freezeEvidence(child);Object.freeze(value);}return value;
}

function normalize(command: AccountingCommand): AccountingCommand {
  for (const key of ["companyId", "bookId", "requestId"] as const) configurationId(command[key], key);
  accountingHash(command.expectedConfigurationDigest);accountingTime(command.businessTime);
  accountingNeed(command.source.system === "fatoora", "Unsupported source system.", "invalid-argument");
  for (const key of ["type", "id", "revision", "action"] as const) configurationId(command.source[key], `source.${key}`);
  return freezeEvidence(JSON.parse(accountingCanonical(command))) as AccountingCommand;
}
function semanticDigest(c: AccountingCommand): string {
  const {requestId: _request, ...economic} = c;return accountingDigest(economic);
}
function pathsFor(c: AccountingCommand, uid: string) {
  const b = `companies/${c.companyId}/books/${c.bookId}`, id = accountingEventId(c.companyId, c.bookId, c.source);
  return {b, id, journal: `${b}/journal_entries/${id}`, event: `${b}/events/${id}`, source: `${b}/source_keys/${id}`,
    request: `${b}/request_keys/request_${accountingDigest([1, uid, c.requestId])}`, audit: `${b}/audit_events/${id}`,
    outbox: `${b}/outbox/${id}`, contract: `${b}/posting_contracts/foundation-v1`};
}
function scope(data: DocumentData | undefined, companyId: string, bookId: string): asserts data is DocumentData {
  accountingNeed(data?.companyId === companyId && data.bookId === bookId, "Accounting reference is outside this book.");
}
function untouched(snapshot: DocumentSnapshot): void {
  accountingNeed(snapshot.exists && snapshot.createTime?.isEqual(snapshot.updateTime!), "Pinned configuration evidence is missing or was overwritten.", "data-loss");
}
function atOrBefore(a: Timestamp, b: Timestamp): boolean {
  return a.seconds < b.seconds || a.seconds === b.seconds && a.nanoseconds <= b.nanoseconds;
}

export async function postAccountingTransaction(db: Firestore, uid: string | undefined, command: AccountingCommand,
  adapter: AccountingPostingAdapter, options: AccountingEmulatorOptions = {}) {
  assertAccountingEmulator(db, options);
  const c = normalize(command);
  const first = await db.runTransaction(t => prepare(t, db, uid, c, adapter, false));
  // A staged callback result is never reported as a committed journal.
  const committed = await recoverAccountingTransaction(db, uid, c, adapter, options);
  accountingSame(first.result, committed.result, "Post-commit result");
  return {...committed, alreadyPosted: first.alreadyPosted};
}

/** Recovery is read-only even when the source/receipt is absent. */
export async function recoverAccountingTransaction(db: Firestore, uid: string | undefined, command: AccountingCommand,
  adapter: AccountingPostingAdapter, options: AccountingEmulatorOptions = {}) {
  assertAccountingEmulator(db, options);
  const c = normalize(command);
  const observed = await db.runTransaction(t => prepare(t, db, uid, c, adapter, true));
  const snapshot = await db.doc(pathsFor(c, uid!).event).get();
  immutableAccountingRecord(snapshot);
  return {...observed, committedAt: {seconds: snapshot.createTime!.seconds, nanoseconds: snapshot.createTime!.nanoseconds}};
}

async function prepare(transaction: Transaction, db: Firestore, uid: string | undefined, c: AccountingCommand,
  adapter: AccountingPostingAdapter, recoveryOnly: boolean): Promise<Decision> {
  accountingNeed((adapter.controlCollections ?? []).every(v => ACCOUNTING_CONTROL_COLLECTIONS.includes(v)), "Unsupported subledger collection declaration.");
  const {tx} = accountingTransaction(transaction, db, c.companyId, c.bookId, adapter.domainPaths, [], adapter.itemPaths ?? []);
  const actor = await requireTrustedUser(tx, db, uid, c.companyId);
  if (actor.role !== "admin") throw new HttpsError("permission-denied", "Only administrators can post accounting settlements.");
  const p = pathsFor(c, actor.uid), digest = semanticDigest(c), requestDigest = accountingDigest(c);
  const [company, sourceKey, request] = await tx.getAll(db.doc(`companies/${c.companyId}`), db.doc(p.source), db.doc(p.request));
  accountingNeed(company.data()?.id === c.companyId && company.data()?.active === true &&
    (company.data()?.companyId === undefined || company.data()?.companyId === c.companyId), "An active correctly scoped company is required.");
  if (request.exists) {
    const r = immutableAccountingRecord(request);
    scope(r, c.companyId, c.bookId);
    if (r.actorUid !== actor.uid || r.requestId !== c.requestId || r.requestDigest !== requestDigest || r.eventId !== p.id) throw new HttpsError("already-exists", "Request identity is already bound to another accounting action.");
    accountingNeed(sourceKey.exists, "A committed request has lost its source binding.", "data-loss");
  }
  if (sourceKey.exists) {
    const result = await recover(tx, db, c, p, digest, sourceKey);
    if (request.exists) accountingSame(immutableAccountingRecord(request).result, result, "Committed request result");
    else if (!recoveryOnly) tx.create(db.doc(p.request), accountingRecord({schemaVersion: 1, environment: ENVIRONMENT,
      companyId: c.companyId, bookId: c.bookId, actorUid: actor.uid, requestId: c.requestId, requestDigest,
      eventId: p.id, aliasOf: immutableAccountingRecord(sourceKey).originalRequestPath, result}));
    return {result, alreadyPosted: true};
  }
  accountingNeed(!recoveryOnly, "No committed accounting action exists; recovery never posts.");
  const [bookSnapshot, seal] = await tx.getAll(db.doc(p.b), db.doc(`${p.b}/posting_contracts/foundation-v1`));
  const book = bookSnapshot.data();scope(book, c.companyId, c.bookId);
  accountingNeed(book.id === c.bookId && book.accountingFoundationVersion === 1 && book.mode === "reconstruction" && book.active === false &&
    book.configurationLocked === true && book.journalPostingEnabled === false && book.foundationEngineEmulatorEnabled === true,
  "A locked synthetic reconstruction book is required; real posting remains disabled.");
  accountingNeed(book.configurationDigest === c.expectedConfigurationDigest && Number.isSafeInteger(book.configurationRevision) && book.configurationRevision > 0, "Configuration changed before posting.");
  const revisionId = `revision_${book.configurationRevision}`;
  accountingNeed(book.policyRevisionId === revisionId && book.fiscalCalendarRevisionId === revisionId, "Book revision references are inconsistent.");
  const [revisionSnapshot, policySnapshot, mappingsSnapshot, lock, definitionSnapshot] = await tx.getAll(
    db.doc(`${p.b}/configuration_revisions/${revisionId}`), db.doc(`${p.b}/policy_revisions/${revisionId}`), db.doc(`${p.b}/account_mappings/${revisionId}`),
    db.doc(`companies/${c.companyId}/maintenance_locks/accounting_posting`), db.doc(`${p.b}/journal_definitions/${adapter.definitionId}`));
  accountingNeed(!lock.exists || lock.data()?.active === false, "Accounting posting is under maintenance.");
  for (const s of [revisionSnapshot, policySnapshot, mappingsSnapshot, definitionSnapshot]) {untouched(s);scope(s.data(), c.companyId, c.bookId);}
  for (const s of [revisionSnapshot, policySnapshot, mappingsSnapshot]) accountingSame(s.data()!.revisionId, revisionId, "Configuration revision identity");
  const configuration = freezeEvidence(validateAccountingConfiguration(revisionSnapshot.data()!.configuration));
  accountingSame(configurationDigest(configuration), c.expectedConfigurationDigest, "Pinned configuration digest");
  accountingSame(revisionSnapshot.data()!.configurationDigest, c.expectedConfigurationDigest, "Configuration revision digest");
  accountingNeed(accountingConfigurationReadiness(configuration).configurationComplete, "The configuration/evidence draft is incomplete.");
  for (const key of ["currency", "moneyScale", "quantityScale", "priceScale", "timezone"] as const) {
    accountingSame(book[key], configuration[key], `Book ${key}`);accountingSame(policySnapshot.data()![key], configuration[key], `Policy ${key}`);
  }
  accountingSame(mappingsSnapshot.data()!.mappings, configuration.mappings, "Pinned account mappings");
  for (const key of ["taxPolicy", "taxCodes", "openingBoundary", "fiscalYearStartMonth", "fiscalYearStartDay"] as const) accountingSame(policySnapshot.data()![key], configuration[key], `Policy ${key}`);
  const accountingDate = accountingLocalDate(c.businessTime);
  accountingNeed(configuration.openingBoundary.cutoverDate! <= accountingDate, "Posting predates the evidenced cutover boundary.");
  const period = configuration.periods.find(r => r.startsOn <= accountingDate && accountingDate < r.endsBefore);
  accountingNeed(period, "No configured accounting period covers this date.");
  const periodSnapshot = await tx.get(db.doc(`${p.b}/periods/${period.id}`)), periodData = periodSnapshot.data();scope(periodData, c.companyId, c.bookId);
  accountingNeed(periodData.id === period.id && periodData.revisionId === revisionId && periodData.status === "open" && periodData.startsOn === period.startsOn && periodData.endsBefore === period.endsBefore, "Accounting period is closed or inconsistent.");
  const definition = definitionSnapshot.data()!;
  accountingNeed(definition.id === adapter.definitionId && definition.active === true && definition.currency === configuration.currency && definition.moneyScale === configuration.moneyScale &&
    definition.numberingPolicy === "source_identity" && Array.isArray(definition.allowedActions) && definition.allowedActions.includes(c.source.action) && Array.isArray(definition.allowedSourceTypes) && definition.allowedSourceTypes.includes(c.source.type) &&
    Array.isArray(definition.allowedControls) && definition.allowedControls.every((v: unknown) => typeof v === "string"), "Journal definition does not authorize this domain action.");
  configurationId(definition.revisionId, "journalDefinitionRevisionId");
  const context: AccountingPostingContext = {companyId: c.companyId, bookId: c.bookId, actor, configuration,
    configurationDigest: c.expectedConfigurationDigest, revisionId, accountingDate, periodId: period.id,
    definitionId: adapter.definitionId, definitionRevisionId: definition.revisionId, allowedControls: definition.allowedControls,
    source: c.source, businessTime: c.businessTime, eventId: p.id};
  const plan = await adapter.prepare(tx, db, context), journal = plan.journal === null ? null : validateAccountingJournal(plan.journal);
  accountingNeed(journal ? (definition.postingKind ?? "financial") === "financial" : definition.postingKind === "quantity", "The journal definition does not authorize this event kind.");
  if (journal) {
  accountingSame(journal.source, c.source, "Journal source");
  for (const key of ["companyId", "bookId", "currency", "moneyScale", "accountingDate", "periodId", "configurationDigest"] as const) {
    accountingSame(journal[key], key === "currency" || key === "moneyScale" ? configuration[key] : context[key], `Journal ${key}`);
  }
  accountingSame(journal.journalDefinitionId, adapter.definitionId, "Journal definition");
  accountingSame(journal.journalDefinitionRevisionId, definition.revisionId, "Journal definition revision");
  }
  const accounts = [...new Map((journal?.lines ?? []).map(l => [l.account.id, l.account])).values()];
  const accountSnapshots = accounts.length ? await tx.getAll(...accounts.map(a => db.doc(`${p.b}/chart_accounts/${a.id}`))) : [];
  for (let i = 0; i < accounts.length; i++) {
    const a = accounts[i], projected = accountSnapshots[i].data(), configured = configuration.accounts.find(v => v.id === a.id);
    accountingNeed(configured && projected && context.allowedControls.includes(a.control), "A journal uses an unconfigured or disallowed control account.");
    const expected: JournalAccount = {...configured, companyId: c.companyId, bookId: c.bookId, revisionId, currency: configuration.currency, moneyScale: configuration.moneyScale};
    accountingSame(a, expected, "Trusted account snapshot");
    for (const [key, value] of Object.entries(expected)) accountingSame(projected[key], value, `Current account ${key}`);
  }
  const count = book.foundationPostingLaneCount;
  accountingNeed(Number.isSafeInteger(count) && count >= 1 && count <= 64, "An explicit bounded posting-lane count is required.");
  const contract = {schemaVersion: 1, companyId: c.companyId, bookId: c.bookId, currency: configuration.currency,
    moneyScale: configuration.moneyScale, quantityScale: configuration.quantityScale, priceScale: configuration.priceScale,
    timezone: configuration.timezone, postingLaneCount: count, inventoryMode: "quantity_only", costCoverage: "not_recorded"};
  const contractDigest = accountingDigest(contract);
  const laneId = `lane_${(parseInt(p.id.slice(6, 14), 16) % count).toString().padStart(2, "0")}`;
  const lanePath = `${p.b}/posting_lanes/${laneId}`;
  const [laneSnapshot, ...targets] = await tx.getAll(db.doc(lanePath), ...[p.journal, p.event, p.audit, p.outbox].map(path => db.doc(path)));
  accountingNeed(targets.every(s => !s.exists), "Accounting artifact collision; no effects can be posted.", "data-loss");
  if (seal.exists) {accountingSame(immutableAccountingRecord(seal).contract, contract, "Immutable monetary/lane contract");accountingSame(book.foundationPostingContractDigest, contractDigest, "Book contract binding");}
  else accountingNeed(book.foundationPostingContractDigest === undefined && !laneSnapshot.exists, "An initialized book has lost its posting contract.", "data-loss");
  let laneSequence = 1, previousEventId: string | null = null, previousEventHash = GENESIS;
  if (laneSnapshot.exists) {
    const lane = laneSnapshot.data()!;scope(lane, c.companyId, c.bookId);
    accountingNeed(lane.id === laneId && lane.contractDigest === contractDigest && Number.isSafeInteger(lane.sequence) && lane.sequence > 0 && lane.sequence < Number.MAX_SAFE_INTEGER, "Posting lane is invalid.", "data-loss");
    previousEventId = configurationId(lane.lastEventId, "previousEventId");previousEventHash = accountingHash(lane.lastEventHash);
    const previous = await tx.get(db.doc(`${p.b}/events/${previousEventId}`)), previousData = immutableAccountingRecord(previous);
    accountingNeed(previousData.lane.id === laneId && previousData.lane.sequence === lane.sequence && laneSnapshot.updateTime!.isEqual(previous.createTime!), "Lane and event committed prefix differ.", "data-loss");
    const {eventHash, ...base} = previousData;accountingSame(accountingDigest(base), eventHash, "Previous event hash");accountingSame(eventHash, previousEventHash, "Lane head hash");
    accountingSame(previousData.contractDigest, contractDigest, "Lane contract");laneSequence = lane.sequence + 1;
  }
  const journalDigest = journal ? accountingDigest(journal) : null;
  const result: AccountingPostingResult = {schemaVersion: 1, companyId: c.companyId, bookId: c.bookId, eventId: p.id,
    journalId: journal ? p.id : null, sourceId: c.source.id, sourceType: c.source.type, laneId, laneSequence,
    economicDigest: digest, journalDigest, configurationDigest: c.expectedConfigurationDigest};
  const binding = {...result, engine: "foundation-v1", environment: ENVIRONMENT};
  const writes = plan.writes(binding);
  accountingNeed(writes.length > 0 && writes.length <= 450 && new Set(writes.map(w => w.path)).size === writes.length, "A bounded, unique domain effect plan is required.");
  const allowed = (path: string) => adapter.domainPaths.includes(path) || (adapter.itemPaths ?? []).includes(path) ||
    path.startsWith(`${p.b}/`) && path.slice(p.b.length + 1).split("/").length === 2 && (adapter.controlCollections ?? []).includes(path.slice(p.b.length + 1).split("/")[0]);
  accountingNeed(writes.every(w => allowed(w.path) && ["create", "set", "update"].includes(w.method)) && writes.some(w => w.path === `companies/${c.companyId}/${c.source.type}/${c.source.id}` && w.method === "create"), "Domain effects must include the immutable original source.");
  for (const w of writes.filter(v => v.path.startsWith("items/"))) accountingNeed(w.data.companyId === c.companyId && w.method === "update", "Catalog quantity updates require explicit company scope.");
  for (const w of writes) if (w.method === "create") accountingSame(w.data.accounting, binding, "Immutable domain accounting binding");
  await verifyAccountingControls(tx, db, context, journal, writes, plan.controlEffects ?? [], plan.stockEffects ?? []);
  const effects = writes.map(w => ({path: w.path, immutable: w.method === "create" && !["open_item_positions", "party_positions"].some(k => w.path.startsWith(`${p.b}/${k}/`)), document: accountingDomainWitness(w.data)}));
  const manifest = prepareEffectManifest(c.companyId, c.bookId, p.id, effects);
  if (manifest.records.length) accountingNeed((await tx.getAll(...manifest.records.map(r => db.doc(r.path)))).every(s => !s.exists), "Atomic effect chunk collision.", "data-loss");
  const baseEvent = {...binding, actor: {uid: actor.uid, name: actor.name, role: actor.role}, source: c.source,
    businessTime: c.businessTime, accountingDate, periodId: period.id, configurationRevisionId: revisionId, journalDefinition: definition,
    semantic: c.semantic, originalRequestPath: p.request, requestDigest, contractDigest, effects: manifest.effects, effectChunks: manifest.effectChunks,
    controlEffects: plan.controlEffects ?? [], stockEffects: plan.stockEffects ?? [], itemPaths: adapter.itemPaths ?? [],
    lane: {id: laneId, sequence: laneSequence, previousEventId, previousEventHash}};
  const event = {...baseEvent, eventHash: accountingDigest(baseEvent)};
  const scopeFields = {schemaVersion: 1, environment: ENVIRONMENT, companyId: c.companyId, bookId: c.bookId, eventId: p.id};
  const artifacts: [string, DocumentData][] = [...(journal ? [[p.journal, {...scopeFields, journal, journalDigest}] as [string, DocumentData]] : []), [p.event, event],
    [p.source, {...scopeFields, economicDigest: digest, originalRequestPath: p.request, result}],
    [p.request, {...scopeFields, actorUid: actor.uid, requestId: c.requestId, requestDigest, aliasOf: null, result}],
    [p.audit, {...scopeFields, action: "accounting_posted", actorUid: actor.uid, journalDigest, economicDigest: digest, eventHash: event.eventHash}],
    [p.outbox, {...scopeFields, projectionIntent: journal ? "project_canonical_journal" : "project_quantity_event", journalDigest, eventHash: event.eventHash}]];
  for (const [, data] of artifacts) accountingRecord(data);
  // All reads are complete. Domain and accounting effects share this SDK commit.
  for (const w of writes) {
    const ref = db.doc(w.path);
    if (w.method === "create") tx.create(ref, w.data);
    else if (w.method === "update") tx.update(ref, w.data);
    else tx.set(ref, w.data, {merge: w.merge === true});
  }
  for (const [path, data] of artifacts) tx.create(db.doc(path), accountingRecord(data));
  for (const record of manifest.records) tx.create(db.doc(record.path), accountingRecord(record.data));
  if (!seal.exists) {tx.create(db.doc(p.contract), accountingRecord({schemaVersion: 1, environment: ENVIRONMENT, companyId: c.companyId, bookId: c.bookId, contract}));tx.update(db.doc(p.b), {foundationPostingContractDigest: contractDigest});}
  for (const s of accountSnapshots) if (s.data()!.used !== true) tx.update(s.ref, {used: true});
  if (periodData.used !== true) tx.update(periodSnapshot.ref, {used: true});
  const head = {schemaVersion: 1, companyId: c.companyId, bookId: c.bookId, id: laneId, sequence: laneSequence,
    contractDigest, lastEventId: p.id, lastEventHash: event.eventHash, updatedAt: FieldValue.serverTimestamp()};
  if (laneSnapshot.exists) tx.update(db.doc(lanePath), head);else tx.create(db.doc(lanePath), head);
  return {result, alreadyPosted: false};
}

async function recover(tx: Transaction, db: Firestore, c: AccountingCommand, p: ReturnType<typeof pathsFor>, digest: string, sourceKey: DocumentSnapshot): Promise<AccountingPostingResult> {
  const source = immutableAccountingRecord(sourceKey);scope(source, c.companyId, c.bookId);
  if (source.economicDigest !== digest) throw new HttpsError("already-exists", "This economic action already has different committed intent.");
  const paths = [p.journal, p.event, p.audit, p.outbox, source.originalRequestPath];
  accountingNeed(typeof source.originalRequestPath === "string" && source.originalRequestPath.startsWith(`${p.b}/request_keys/`), "Original request reference is invalid.", "data-loss");
  const snapshots = await tx.getAll(...paths.map(path => db.doc(path))), [journalSnapshot, eventSnapshot, auditSnapshot, outboxSnapshot, originalRequest] = snapshots;
  const [event, audit, outbox, request] = [eventSnapshot, auditSnapshot, outboxSnapshot, originalRequest].map(immutableAccountingRecord), commit = eventSnapshot.createTime!;
  const hasJournal = source.result.journalId !== null;
  accountingNeed(hasJournal ? journalSnapshot.exists : !journalSnapshot.exists && event.journalDefinition.postingKind === "quantity", "Committed journal presence is inconsistent.", "data-loss");
  const j = hasJournal ? immutableAccountingRecord(journalSnapshot) : null;
  for (const s of [sourceKey, ...(hasJournal ? [journalSnapshot] : []), auditSnapshot, outboxSnapshot, originalRequest]) accountingNeed(s.createTime!.isEqual(commit), "Financial artifacts were not created atomically.", "data-loss");
  for (const d of [...(j ? [j] : []), event, audit, outbox, request]) {scope(d, c.companyId, c.bookId);accountingNeed(d.eventId === p.id && d.environment === ENVIRONMENT, "Accounting artifact identity is invalid.", "data-loss");}
  const journal = j ? validateAccountingJournal(j.journal) : null, journalDigest = journal ? accountingDigest(journal) : null;
  const configurationRevisionId = configurationId(event.configurationRevisionId, "committed configuration revision");
  const configurationSnapshot = await tx.get(db.doc(`${p.b}/configuration_revisions/${configurationRevisionId}`));untouched(configurationSnapshot);
  accountingNeed(atOrBefore(configurationSnapshot.createTime!, commit), "Original configuration was recreated after the event.", "data-loss");
  scope(configurationSnapshot.data(), c.companyId, c.bookId);
  const originalConfiguration = validateAccountingConfiguration(configurationSnapshot.data()!.configuration);
  accountingSame(configurationDigest(originalConfiguration), c.expectedConfigurationDigest, "Original configuration evidence");
  accountingSame(configurationSnapshot.data()!.configurationDigest, c.expectedConfigurationDigest, "Original configuration witness");
  if (journal) {
  accountingSame(journal.journalDefinitionRevisionId, event.journalDefinition.revisionId, "Original journal definition revision");
  accountingSame(journal.source, c.source, "Recovered source");accountingSame(journal.configurationDigest, c.expectedConfigurationDigest, "Recovered configuration");
  }
  accountingSame(event.semantic, c.semantic, "Recovered economic input");accountingSame(event.businessTime, c.businessTime, "Recovered business time");
  accountingSame(event.accountingDate, accountingLocalDate(c.businessTime), "Recovered accounting date");
  const {eventHash, ...base} = event;accountingSame(accountingDigest(base), eventHash, "Committed event hash");
  if (j) accountingSame(j.journalDigest, journalDigest, "Committed journal digest");accountingSame(event.journalDigest, journalDigest, "Event journal digest");
  for (const d of [audit, outbox]) {accountingSame(d.journalDigest, journalDigest, "Artifact journal digest");accountingSame(d.eventHash, eventHash, "Artifact event hash");}
  const seal = await tx.get(db.doc(p.contract)), sealed = immutableAccountingRecord(seal);
  accountingNeed(atOrBefore(seal.createTime!, commit), "Posting contract was recreated after the event.", "data-loss");
  accountingSame(accountingDigest(sealed.contract), event.contractDigest, "Committed contract digest");
  const effects = await readAccountingEffects(tx, db, eventSnapshot, event);
  accountingNeed(effects.length > 0 && effects.length <= 450 && effects.some(e => e.path === `companies/${c.companyId}/${c.source.type}/${c.source.id}` && e.immutable), "Committed effect manifest is invalid.", "data-loss");
  for (const e of effects) accountingNeed(typeof e.path === "string" && (e.path.startsWith(`companies/${c.companyId}/`) || !e.immutable && (event.itemPaths ?? []).includes(e.path)) && !immutableCollections.some(k => e.path.startsWith(`${p.b}/${k}/`)), "Committed domain path is invalid.", "data-loss");
  const immutableEffects = effects.filter(e => e.immutable), documents = await tx.getAll(...immutableEffects.map(e => db.doc(e.path)));
  for (let i = 0; i < documents.length; i++) {
    const s = documents[i];untouched(s);accountingNeed(s.createTime!.isEqual(commit), "Domain effect did not commit with the journal.", "data-loss");
    accountingSame(accountingDomainWitness(s.data()!), immutableEffects[i].document, "Committed domain effect");
  }
  const result = source.result as AccountingPostingResult;
  accountingSame(request.result, result, "Original committed result");
  accountingSame(result, {schemaVersion: 1, companyId: c.companyId, bookId: c.bookId, eventId: p.id, journalId: hasJournal ? p.id : null,
    sourceId: c.source.id, sourceType: c.source.type, laneId: event.lane.id, laneSequence: event.lane.sequence,
    economicDigest: digest, journalDigest, configurationDigest: c.expectedConfigurationDigest}, "Reconstructed committed result");
  return result;
}
