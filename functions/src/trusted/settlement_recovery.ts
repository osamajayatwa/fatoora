import {DocumentData, DocumentReference, DocumentSnapshot, Firestore, Query, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {prepareCommittedSettlementRecovery, assertSettlementRecoveryEmulator} from "./settlement_journal_persistence";
import {PendingSettlementRequest, PendingSettlementEvidence, normalizePendingSettlementRequest,
  canonicalSettlementEvidence as canonical, settlementEvidenceDigest as digest} from "./settlement_pending_evidence";
import {buildSettlementJournalIntent} from "./settlement_journal_intent";
import {Time, compare, freeze, id, money, periodContains, readSettlementPositions, required, time} from "./settlement_preflight_shared";

export interface SettlementRecoveryOptions {enableEmulatorRecovery?: boolean}

/** Internal, bounded transaction verification, never a historical clearance.
 * No writable transaction or write plan is exposed to this module's callers. */
export async function recoverSettlementTransaction(
  db: Firestore, uid: string | undefined, input: PendingSettlementRequest,
  expectedEvidence?: unknown, options: SettlementRecoveryOptions = {},
) {
  if (options.enableEmulatorRecovery !== true) throw new HttpsError("failed-precondition", "Settlement recovery is disabled by default.");
  assertSettlementRecoveryEmulator(db);
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  const n = normalizePendingSettlementRequest(input, uid);
  const request = freeze({...input, settlementDate: {...n.date}});
  const expected = expectedEvidence === undefined ? undefined : JSON.parse(canonical(expectedEvidence));
  // Read-only SDK transactions do not retry. Retry only transport contention,
  // with fresh authorization/snapshot/cache and the original pinned request.
  for (let attempt = 0; ; attempt++) {
    try {
      return await db.runTransaction(async raw => {
        const reader = readOnlyReader(raw, db, n.companyId);
        const recovered = await prepareCommittedSettlementRecovery(reader.tx, db, uid, request, expected);
        const original = required(await reader.read(`companies/${n.companyId}/settlements/${recovered.result.settlementId}`));
        const originalRequest = normalizePendingSettlementRequest(request, id(original.createdByUid, "Original posting actor"));
        const verification = await independentlyVerify(reader.read, reader.linked, originalRequest, recovered);
        return freeze({...recovered, verification, observation: {
          transactionReadTime: time((await reader.read(`companies/${n.companyId}`)).readTime),
          documentReads: reader.documentCount(), queryReads: reader.queryCount(),
        }});
      }, {readOnly: true});
    } catch (error) {
      const failure = error as {code?: unknown; details?: unknown; message?: unknown};
      const retry = failure.code === 10 || failure.code === 3 &&
        (failure.details === "Transaction is invalid or closed." || failure.message === "3 INVALID_ARGUMENT: Transaction is invalid or closed.");
      if (!retry || attempt >= 4) throw error;
    }
  }
}

type Read = (path: string) => Promise<DocumentSnapshot>;
type Linked = (collection: string, field: string, value: string, paths: string[]) => Promise<void>;
type Recovered = Awaited<ReturnType<typeof prepareCommittedSettlementRecovery>>;

async function independentlyVerify(read: Read, linked: Linked,
  n: ReturnType<typeof normalizePendingSettlementRequest>, recovered: Recovered) {
  const {result: r, commit} = recovered, c = `companies/${n.companyId}`, b = `${c}/books/${r.bookId}`;
  const source = required(await read(`${c}/settlements/${r.settlementId}`));
  const event = required(await read(`${b}/events/${r.eventId}`));
  const e = event.pendingEvidence as PendingSettlementEvidence;
  const movements = await Promise.all([source.repMovementId, source.companyMovementId].map(async value =>
    required(await read(`${c}/cash_movements/${id(value, "Source movement")}`))));
  const intent = buildSettlementJournalIntent({companyId: n.companyId, bookId: r.bookId,
    policy: e.economics.policy, mappings: e.economics.lines.map(l => l.account), settlement: source, movements});
  const {schemaVersion, id: entryId, companyId, bookId, action, currency, moneyScale, amountUnits, policy, lines} = intent;
  same(e.economics, {schemaVersion, id: entryId, companyId, bookId, action, currency, moneyScale, amountUnits, policy, lines}, "Reconstructed economics");
  same(e.source, {collection: "settlements", id: source.id, path: `${c}/settlements/${source.id}`,
    operationId: source.operationId, status: "pending", number: source.settlementNumber, idempotencyKey: source.idempotencyKey,
    notes: source.notes, salesRepId: source.salesRepId, salesRepName: source.salesRepName,
    actor: intent.source.provenance.createdBy, settlementMetadataVersion: 1, postingSource: "recordCashSettlement", paymentMethod: "cash",
    sellerId: "", sellerName: "", collectorUid: "", collectorName: "", sellerIdentityStatus: "not_applicable", collectorIdentityStatus: "not_applicable"}, "Original pending source");
  same(e.timestamps, {accountingDate: intent.source.settlementDate, sourceRecordedAt: null, sourceCommittedAt: null,
    journalRecordedAt: null, journalCommittedAt: null}, "Pending clocks");
  same(e.timestampContract, {recordedFields: "server_transform_in_future_atomic_write", actualCommitMetadata: "trusted_sdk_metadata_only_after_commit",
    recordedEqualsCommit: false}, "Pending timestamp contract");
  same(e.schemaVersion, 1, "Evidence schema");same(e.mode, "pending_settlement", "Evidence mode");
  same(e.requestDigest, n.requestDigest, "Request digest");
  same(e.economicDigest, digest({schemaVersion: 1, source: e.source, economics: e.economics, accountingDate: n.date}), "Independent economic digest");
  periodContains(e.context, n.date);
  same(policy.revisionId, e.context.policyRevisionId, "Policy revision");
  same(policy.legacyCurrencyBindingId ?? null, e.context.legacyCurrencyBindingRevisionId, "Legacy currency evidence");
  for (const line of lines) same(line.account.mappingRevisionId, e.context.mappingRevisionId, "Account mapping revision");

  // Reconstruct original before positions from independently stored predecessor
  // movements; today's cash balances cannot establish an old settlement's before.
  check(e.positions.length === 2, "Exactly two original positions required.");
  const positionPaths = [`${c}/cash_balances/rep_${n.rep}`, `${c}/cash_balances/company_cash`];
  const predecessorPaths: string[] = [];
  for (const [i, p] of e.positions.entries()) {
    same(p.path, positionPaths[i], "Position scope");
    const predecessorPath = `${c}/cash_movements/${id(p.lastMovementId, "Predecessor")}`;
    predecessorPaths.push(predecessorPath);
    const snap = await read(predecessorPath), head = required(snap);
    immutable(snap);check(compare(time(snap.createTime), commit.committedAt) < 0, "Original cash predecessor must predate settlement.");
    cashIdentity(head, snap.id, companyId, i === 0 ? n.rep : "");
    cashEquation(head);
    same(p, {path: positionPaths[i], amountUnits: money(head.balanceAfter).toString(), lastMovementId: snap.id,
      updatedAt: time(head.createdAt), headRecordedAt: time(head.createdAt), headCommittedAt: time(snap.createTime),
      balanceCommittedAt: time(snap.createTime)}, "Original cash position witness");
    same(money(movements[i].balanceBefore).toString(), p.amountUnits, "Original cash continuity");
  }
  const effects = intent.movements.map(m => ({id: m.id, path: m.path, direction: m.direction, cashAccount: m.cashAccount,
    treasuryAccountId: m.treasuryAccountId, holderType: m.holderType, holderUid: m.holderUid,
    counterpartMovementId: m.counterpartMovementId, amountUnits: m.amountUnits,
    balanceBeforeUnits: m.balanceBeforeUnits, balanceAfterUnits: m.balanceAfterUnits}));
  same(e.cashEffects, effects, "Reconstructed original cash effects");
  const total = (field: "balanceBeforeUnits" | "balanceAfterUnits") => effects.reduce((sum, v) => sum + BigInt(v[field]), 0n).toString();
  same(total("balanceBeforeUnits"), total("balanceAfterUnits"), "Custody conservation");

  const targets = {settlement: e.source.path, repMovement: `${c}/cash_movements/${source.id}_rep_out`,
    companyMovement: `${c}/cash_movements/${source.id}_company_in`, legacyLedger: `${c}/financial_ledger_entries/settlement_${source.id}_transfer`,
    sourceKey: `${b}/source_keys/${entryId}`, journal: `${b}/journal_entries/${entryId}`, event: `${b}/events/${entryId}`};
  same(e.targets, targets, "Deterministic targets");
  const configPaths = [...new Set([c, b, `${b}/policy_revisions/${id(e.context.policyRevisionId, "Policy")}`,
    `${b}/settlement_mappings/${id(e.context.mappingRevisionId, "Mapping")}`, `${b}/periods/${id(e.context.period.id, "Period")}`,
    `${c}/maintenance_locks/cash_reconciliation`, `users/${e.source.actor.uid}`, `users/${n.rep}`,
    ...lines.map(l => `${b}/chart_accounts/${id(l.account.accountId, "Account")}`),
    ...(policy.legacyCurrencyBindingId ? [`${b}/currency_bindings/${id(policy.legacyCurrencyBindingId, "Binding")}`] : [])])];
  const expectedPaths = [...new Set([...configPaths, ...positionPaths, ...predecessorPaths, ...Object.values(targets)])].sort();
  same(e.versions.map(v => v.path), expectedPaths, "Complete bounded version witness set");
  const configVersions = e.versions.filter(v => configPaths.includes(v.path));
  const configurationVersions: {path: string; state: "unchanged" | "changed_since_posting" | "absent_at_posting"}[] = [];
  for (const v of e.versions) {
    if (Object.values(targets).includes(v.path)) {same(v.updateTime, null, "Targets absent at preflight");continue;}
    if (v.updateTime === null) {
      same(v.path, `${c}/maintenance_locks/cash_reconciliation`, "Only lock may lack configuration");
      configurationVersions.push({path: v.path, state: "absent_at_posting"});continue;
    }
    check(compare(time(v.updateTime), commit.committedAt) < 0, "Preflight version must precede settlement.");
    const p = e.positions.find(position => position.path === v.path);
    if (p) same(v.updateTime, p.balanceCommittedAt, "Original position version");
    else if (predecessorPaths.includes(v.path)) same(v.updateTime, time((await read(v.path)).updateTime), "Original head version");
    else {
      const current = await read(v.path);
      check(current.exists && compare(time(current.createTime), v.updateTime) <= 0, "Configuration witness is missing or recreated.");
      const unchanged = compare(time(current.updateTime), v.updateTime) === 0;
      if (unchanged) verifyOriginalConfiguration(v.path, required(current), e, c, b);
      configurationVersions.push({path: v.path, state: unchanged ? "unchanged" : "changed_since_posting"});
    }
  }
  same(e.configurationDigest, digest({schemaVersion: 1, context: e.context, policy,
    accounts: lines.map(l => l.account), versions: configVersions}), "Independent configuration digest");
  same(e.preflightDigest, digest({schemaVersion: 1, mode: "pending_settlement", economicDigest: e.economicDigest,
    configurationDigest: e.configurationDigest, positions: e.positions, cashEffects: effects, versions: e.versions, targets}), "Independent preflight digest");
  await verifyDefinitionAndLane(read, b, event, e, commit.committedAt);
  const current = await readSettlementPositions(async paths => Promise.all(paths.map(read)), {
    companyId, bookId, c, b, companySnapshot: await read(c), mapping: {}, policy, context: e.context,
  }, n.rep);
  for (const [i, p] of current.positions.entries()) {
    check(compare(p.headCommittedAt, commit.committedAt) >= 0, "Current cash head predates settlement.");
    const snap = await read(`${c}/cash_movements/${p.lastMovementId}`);immutable(snap);
    if (compare(p.headCommittedAt, commit.committedAt) === 0) same(p.lastMovementId, movements[i].id, "Original current cash head");
  }
  // Bounded, company/book-local duplicate probes. Hidden/unlinked records and
  // other books require a complete historical scan; these probes claim neither.
  await linked(`${c}/cash_movements`, "sourceId", source.id, [targets.repMovement, targets.companyMovement]);
  await linked(`${c}/settlements`, "idempotencyKey", n.key, [targets.settlement]);
  await linked(`${c}/financial_ledger_entries`, "sourceId", source.id, [targets.legacyLedger]);
  for (const collection of ["journal_entries", "events", "source_keys", "request_keys", "audit_events", "outbox"]) {
    await linked(`${b}/${collection}`, "sourceId", source.id,
      [`${b}/${collection}/${collection === "request_keys" ? r.requestId : entryId}`]);
  }
  return {scope: "transaction" as const, historicalReconciliation: "not_performed" as const,
    effectDigest: event.reconciliation.effectDigest, debitUnits: amountUnits, creditUnits: amountUnits,
    totalCashBeforeUnits: total("balanceBeforeUnits"), totalCashAfterUnits: total("balanceAfterUnits"),
    configurationEvidence: "commit_bound_snapshot_and_version_witnesses" as const, configurationVersions,
    currentPositions: current.positions};
}

async function verifyDefinitionAndLane(read: Read, b: string, event: DocumentData, e: PendingSettlementEvidence, commit: Time) {
  const definition = await read(`${b}/journal_definitions/${id(event.definition.id, "Definition")}`);immutable(definition);
  same(time(definition.updateTime), event.definition.snapshotVersion, "Definition SDK witness");
  check(compare(time(definition.createTime), commit) <= 0, "Definition created after posting.");
  const data = required(definition);
  for (const [key, value] of Object.entries({id: event.definition.id, companyId: e.economics.companyId, bookId: e.economics.bookId,
    revisionId: event.definition.revisionId, approvalStatus: "approved", active: true, action: "rep_to_company_cash",
    currency: e.economics.currency, moneyScale: 3, numberingPolicy: "source_identity"})) same(data[key], value, `Definition ${key}`);
  const contract = event.contract, lane = event.lane;
  check(Number.isSafeInteger(contract.postingLaneCount) && contract.postingLaneCount >= 1 && contract.postingLaneCount <= 64, "Bounded lane count required.");
  same(contract, {schemaVersion: 1, companyId: e.economics.companyId, bookId: e.economics.bookId, currency: e.economics.currency,
    moneyScale: 3, postingLaneCount: contract.postingLaneCount, postingLaneSchemaVersion: 1, journalEntrySchemaVersion: 1}, "Original monetary/lane contract");
  same(event.contractDigest, digest(contract), "Independent contract digest");
  const expectedLane = `lane_${(parseInt(digest(e.id).slice(0, 8), 16) % contract.postingLaneCount).toString().padStart(2, "0")}`;
  same(lane.id, expectedLane, "Deterministic lane");
  check(Number.isSafeInteger(lane.sequence) && lane.sequence >= 1, "Valid lane sequence required.");
  if (lane.sequence === 1) {same(lane.previousEventId, null, "Genesis predecessor");same(lane.previousEventHash, "0".repeat(64), "Genesis hash");}
  else {
    const snap = await read(`${b}/events/${id(lane.previousEventId, "Previous event")}`);immutable(snap);
    const previous = required(snap);validateEvent(previous);
    check(compare(time(snap.createTime), commit) < 0, "Lane predecessor must predate event.");
    for (const [key, value] of Object.entries({companyId: e.economics.companyId, bookId: e.economics.bookId, eventId: snap.id,
      contractDigest: event.contractDigest, eventHash: lane.previousEventHash})) same(previous[key], value, `Predecessor ${key}`);
    same(previous.lane.id, lane.id, "Predecessor lane");same(previous.lane.sequence, lane.sequence - 1, "Predecessor sequence");
  }
  const book = required(await read(b));same(book.settlementPostingContract, {
    schemaVersion: 1, path: `${b}/posting_contracts/settlement-v1`, digest: event.contractDigest}, "Book seal binding");
  const head = await read(`${b}/posting_lanes/${expectedLane}`), h = required(head);
  for (const [key, value] of Object.entries({schemaVersion: 1, id: expectedLane, companyId: e.economics.companyId,
    bookId: e.economics.bookId, currency: e.economics.currency, moneyScale: 3, contractDigest: event.contractDigest})) same(h[key], value, `Lane head ${key}`);
  check(Number.isSafeInteger(h.sequence) && h.sequence >= lane.sequence, "Lane head precedes event.");
  const headEvent = await read(`${b}/events/${id(h.lastEventId, "Head event")}`);immutable(headEvent);
  const payload = required(headEvent);validateEvent(payload);
  same(time(head.updateTime), time(headEvent.createTime), "Atomic lane head witness");
  for (const [key, value] of Object.entries({companyId: e.economics.companyId, bookId: e.economics.bookId,
    eventId: headEvent.id, contractDigest: event.contractDigest, eventHash: h.lastEventHash})) same(payload[key], value, `Head event ${key}`);
  same(payload.lane.id, expectedLane, "Head event lane");same(payload.lane.sequence, h.sequence, "Head event sequence");
  if (h.sequence === lane.sequence) same(h.lastEventId, e.id, "Original lane head");
}

/** Validate raw configuration whenever its original SDK version still exists.
 * Changed mutable records remain explicitly version witnesses, never a claim
 * that their historical raw contents were independently retrieved. */
function verifyOriginalConfiguration(path: string, data: DocumentData, e: PendingSettlementEvidence, c: string, b: string): void {
  const {companyId, bookId, currency, policy, lines} = e.economics;
  const fields = (expected: DocumentData) => {for (const [key, value] of Object.entries(expected)) same(data[key], value, `Original configuration ${key}`);};
  if (path.startsWith("users/")) {
    const actor = path === `users/${e.source.actor.uid}`;
    fields({companyId, role: actor ? "admin" : "sales_rep", active: true, approvalStatus: "approved"});
    if (data.uid !== undefined) same(data.uid, path.slice(6), "Original profile identity");
    const name = typeof data.name === "string" ? data.name.trim() : "";
    const email = actor && typeof data.email === "string" ? data.email.trim() : "";
    same(name || email || path.slice(6),
      actor ? e.source.actor.name : e.source.salesRepName, "Original profile name");return;
  }
  if (path === `${c}/maintenance_locks/cash_reconciliation`) {fields({active: false});return;}
  if (path === c) {fields({id: companyId, active: true, activeBookId: bookId});return;}
  fields({id: path.slice(path.lastIndexOf("/") + 1), companyId, approvalStatus: "approved"});
  if (path === b) {
    fields({revisionId: e.context.bookRevisionId, active: true, mode: "configuration", settlementPreflightEnabled: true,
      journalPostingEnabled: false, currency, moneyScale: 3, policyRevisionId: e.context.policyRevisionId,
      settlementMappingRevisionId: e.context.mappingRevisionId, settlementPeriodId: e.context.period.id});return;
  }
  fields({bookId});
  if (path.includes("/policy_revisions/")) {
    fields({revisionId: policy.revisionId, currency, moneyScale: 3, accountingDateBasis: "settlement_business_date"});
    same(data.legacyCurrencyBindingId ?? null, e.context.legacyCurrencyBindingRevisionId, "Original currency binding pin");
  } else if (path.includes("/settlement_mappings/")) {
    fields({revisionId: e.context.mappingRevisionId, companyCashAccountId: lines[0].account.accountId,
      companyCashAccountRevisionId: lines[0].account.accountRevisionId, representativeCashAccountId: lines[1].account.accountId,
      representativeCashAccountRevisionId: lines[1].account.accountRevisionId});
  } else if (path.includes("/chart_accounts/")) {
    const account = lines.find(l => l.account.accountId === data.id)!.account;
    fields({revisionId: account.accountRevisionId, currency, moneyScale: 3, accountType: "asset", control: "cash", active: true,
      postingAllowed: true, requiresTreasuryDimension: true});
  } else if (path.includes("/currency_bindings/")) {
    fields({revisionId: e.context.legacyCurrencyBindingRevisionId, sourceCollection: "settlements", postingSource: "recordCashSettlement",
      settlementMetadataVersion: 1, currency, moneyScale: 3});
  } else if (path.includes("/periods/")) {
    fields({revisionId: e.context.period.revisionId, status: "open"});
    same(time(data.startsAt), e.context.period.startsAt, "Original period start");same(time(data.endsAt), e.context.period.endsAt, "Original period end");
  }
}

function validateEvent(data: DocumentData): void {
  const {recordDigest, recordedAt, committedAt, ...raw} = data;
  const payload = {...raw, accountingDate: time(raw.accountingDate)};
  const {eventHash, ...base} = payload as DocumentData;
  same(recordDigest, digest(payload), "Adjacent event digest");same(eventHash, digest(base), "Adjacent event hash");
  same(committedAt, null, "Adjacent unknown commit clock");time(recordedAt);
}
function cashIdentity(data: DocumentData, documentId: string, companyId: string, rep: string): void {
  for (const [key, value] of Object.entries({id: documentId, companyId, cashAccount: rep ? "rep_cash" : "company_cash", salesRepId: rep})) same(data[key], value, `Cash predecessor ${key}`);
  for (const [key, value] of Object.entries({holderType: rep ? "representative" : "company", holderUid: rep || companyId,
    treasuryAccountId: rep ? `rep_${rep}` : "company_cash"})) if (data[key] !== undefined) same(data[key], value, `Cash predecessor ${key}`);
}
function cashEquation(data: DocumentData): void {
  check(data.direction === "in" || data.direction === "out", "Cash direction required.");
  const amount = money(data.amount), before = money(data.balanceBefore), after = money(data.balanceAfter);
  check(amount > 0n && before >= 0n && after >= 0n, "Nonnegative cash custody required.");
  same((before + (data.direction === "in" ? amount : -amount)).toString(), after.toString(), "Exact cash equation");
}
function immutable(snapshot: DocumentSnapshot): void {
  check(snapshot.exists && compare(time(snapshot.createTime), time(snapshot.updateTime)) === 0, "Missing or overwritten immutable witness.");
  const data = required(snapshot);
  for (const field of ["createdAt", "postedAt", "recordedAt"]) if (data[field] !== undefined)
    check(compare(time(data[field]), time(snapshot.createTime)) <= 0, "Recorded clock exceeds SDK commit witness.");
}
function same(actual: unknown, expected: unknown, label: string): void {check(canonical(actual) === canonical(expected), `${label} is inconsistent.`);}
function check(condition: boolean, message: string): asserts condition {if (!condition) throw new HttpsError("data-loss", message);}

function readOnlyReader(raw: Transaction, db: Firestore, companyId: string) {
  const snapshots = new Map<string, DocumentSnapshot>();let queries = 0;
  const readAll = async (refs: DocumentReference[]) => {
    check(refs.every(r => typeof r?.path === "string" && (r.path.startsWith(`companies/${companyId}/`) || r.path === `companies/${companyId}` || /^users\/[^/]+$/.test(r.path))), "Unscoped document read rejected.");
    const missing = [...new Map(refs.filter(r => !snapshots.has(r.path)).map(r => [r.path, r])).values()];
    check(snapshots.size + missing.length <= 64, "Recovery document budget exceeded.");
    if (missing.length) for (const s of await raw.getAll(...missing)) snapshots.set(s.ref.path, s);
    return refs.map(r => snapshots.get(r.path)!);
  };
  const read: Read = async path => (await readAll([db.doc(path)]))[0];
  const linked: Linked = async (collection, field, value, paths) => {
    check(collection.startsWith(`companies/${companyId}/`) && ++queries <= 9, "Recovery query budget exceeded.");
    const result = await raw.get(db.collection(collection).where(field, "==", value).select().limit(paths.length + 1));
    same(result.docs.map(s => s.ref.path).sort(), [...paths].sort(), "Duplicate or partially linked evidence");
  };
  const tx = new Proxy(raw, {get(target, prop) {
    if (["create", "set", "update", "delete"].includes(String(prop))) return () => {throw new HttpsError("failed-precondition", "Settlement recovery cannot write.");};
    if (prop === "get") return async (ref: DocumentReference | Query) => {
      check("path" in ref && typeof ref.path === "string", "Recovery accepts planned document reads only.");
      return (await readAll([ref as DocumentReference]))[0];
    };
    if (prop === "getAll") return (...refs: DocumentReference[]) => readAll(refs);
    const value = Reflect.get(target, prop);return typeof value === "function" ? value.bind(target) : value;
  }});
  return {tx, read, linked, documentCount: () => snapshots.size, queryCount: () => queries};
}
