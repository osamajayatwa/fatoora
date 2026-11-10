"use strict";
const assert = require("node:assert/strict");
const {test, after} = require("node:test");
const {randomUUID} = require("node:crypto");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
// No Admin client may initialize until a dedicated loopback emulator is selected.
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) {
  throw new Error("Atomic settlement tests require an isolated loopback Firestore emulator.");
}
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {recordCashSettlementTransaction: legacyPost} = require("../lib/trusted/record_cash_settlement");
const {pendingSettlementEvidenceTransaction: prepare, settlementEvidenceDigest: evidenceDigest} = require("../lib/trusted/settlement_pending_evidence");
const {preflightSettlementTransaction: committedPreflight} = require("../lib/trusted/settlement_preflight");
const {buildSettlementJournalIntent} = require("../lib/trusted/settlement_journal_intent");
const {persistSettlementJournalTransaction: persist, prepareSettlementJournalPersistence: compose} = require("../lib/trusted/settlement_journal_persistence");
const app = initializeApp({projectId: "demo-fatoora-phase2b7"}, "atomic-settlement-tests");
const db = getFirestore(app);
after(() => deleteApp(app));
const enabled = Object.freeze({enableEmulatorPersistence: true});
const date = new Timestamp(Timestamp.fromDate(new Date("2026-08-05T12:00:00Z")).seconds, 123456000);
const time = t => ({seconds: t.seconds, nanoseconds: t.nanoseconds});
const clone = value => JSON.parse(JSON.stringify(value));
const errorCode = expected => error => {assert.equal(error.code, expected, error.stack);return true;};

const {createSettlementFixture} = require("./helpers/settlement_fixture");
const fixture = () => createSettlementFixture(db, date);

const financialCollections = ["settlements", "cash_movements", "cash_balances", "financial_ledger_entries",
  "books/synthetic-book/journal_entries", "books/synthetic-book/events", "books/synthetic-book/source_keys",
  "books/synthetic-book/outbox", "books/synthetic-book/request_keys", "books/synthetic-book/audit_events",
  "books/synthetic-book/posting_lanes", "books/synthetic-book/posting_contracts"];
async function financialSnapshot(f) {
  const result = [];
  for (const name of financialCollections) {
    const snapshots = await db.collection(`${f.c}/${name}`).get();
    result.push(...snapshots.docs.map(s => ({path: s.ref.path, version: time(s.updateTime), data: s.data()})));
  }
  return result.sort((a, b) => a.path.localeCompare(b.path));
}
async function counts(f) {
  const result = {};
  for (const name of financialCollections) result[name.split("/").at(-1)] = (await db.collection(`${f.c}/${name}`).get()).size;
  return result;
}
function proxyTransaction(t, overrides) {
  return new Proxy(t, {get(target, name) {const value = overrides[name] || Reflect.get(target, name, target);
    return typeof value === "function" ? value.bind(target) : value;}});
}
function wrapped(run, extra = {}) {
  return new Proxy(db, {get(target, name) {
    if (Object.hasOwn(extra, name)) return extra[name];
    if (name === "runTransaction") return (callback, options) => run(callback, options);
    const value = Reflect.get(target, name, target);return typeof value === "function" ? value.bind(target) : value;
  }});
}
function accountingPaths(f, e, r) {
  return {...e.targets, request: `${f.b}/request_keys/${r.result.requestId}`,
    audit: `${f.b}/audit_events/${e.id}`, outbox: `${f.b}/outbox/${e.id}`,
    lane: `${f.b}/posting_lanes/${r.result.laneId}`, seal: f.paths.seal};
}

test("atomic settlement preserves existing effects and commits exactly one balanced durable journal and complete references", async () => {
  const f = await fixture(), e = await f.review(), r = await f.persist({}, e), paths = accountingPaths(f, e, r);
  assert.equal(r.recovered, false);assert.equal(r.result.settlementId, e.source.id);
  assert.equal(r.result.companyId, f.company);assert.equal(r.result.bookId, f.bookId);
  assert.equal(r.result.journalId, e.id);assert.equal(r.result.eventId, e.id);assert.equal(r.result.sourceKeyPath, e.targets.sourceKey);
  for (const key of ["requestDigest", "economicDigest", "preflightDigest"]) assert.equal(r.result[key], e[key]);
  const docs = Object.fromEntries(await Promise.all(Object.entries(paths).map(async ([name, path]) => [name, await db.doc(path).get()])));
  for (const [name, snapshot] of Object.entries(docs)) assert.equal(snapshot.exists, true, name);
  const source = docs.settlement.data(), out = docs.repMovement.data(), incoming = docs.companyMovement.data(), journal = docs.journal.data();
  assert.equal(source.status, "posted");assert.equal(source.amount, 1.234);assert.equal(source.salesRepId, f.rep);
  assert.equal(source.settlementNumber, e.source.number);assert.deepEqual(time(source.settlementDate), time(date));
  assert.equal(source.postedByUid, f.admin);assert.equal(source.sellerIdentityStatus, "not_applicable");assert.equal(source.collectorIdentityStatus, "not_applicable");
  assert.equal(out.direction, "out");assert.equal(incoming.direction, "in");assert.equal(out.holderUid, f.rep);assert.equal(incoming.holderUid, f.company);
  assert.equal(out.counterpartMovementId, incoming.id);assert.equal(incoming.counterpartMovementId, out.id);
  assert.equal(out.balanceBefore, 69.988);assert.equal(out.balanceAfter, 68.754);assert.equal(incoming.balanceBefore, 50.345);assert.equal(incoming.balanceAfter, 51.579);
  assert.equal(journal.amountUnits, "1234");assert.equal(journal.currency, "JOD");assert.equal(journal.moneyScale, 3);
  assert.deepEqual(journal.lines, e.economics.lines);
  assert.equal(journal.lines.reduce((sum, line) => sum + BigInt(line.debitUnits) - BigInt(line.creditUnits), 0n), 0n);
  assert.deepEqual(journal.lines.map(l => [l.account.holderUid, l.debitUnits, l.creditUnits]), [[f.company, "1234", "0"], [f.rep, "0", "1234"]]);
  const event = docs.event.data();assert.deepEqual(event.pendingEvidence, e);assert.ok(event.reconciliation);
  assert.equal(event.links.journal, paths.journal);assert.equal(event.links.sourceKey, paths.sourceKey);
  assert.deepEqual(event.reconciliation.cashMovementPaths, [paths.repMovement, paths.companyMovement]);
  assert.deepEqual(event.reconciliation.cashPositionPaths, [f.paths.repBalance, f.paths.companyBalance]);
  assert.equal(event.reconciliation.sourcePath, paths.settlement);assert.equal(event.reconciliation.legacyLedgerPath, paths.legacyLedger);
  assert.equal(event.reconciliation.journalPath, paths.journal);assert.equal(event.reconciliation.debitUnits, "1234");assert.equal(event.reconciliation.creditUnits, "1234");
  assert.equal(event.reconciliation.totalCashBeforeUnits, "120333");assert.equal(event.reconciliation.totalCashAfterUnits, "120333");
  assert.deepEqual(event.reconciliation.cashEffects, e.cashEffects);assert.match(event.reconciliation.effectDigest, /^[a-f0-9]{64}$/);
  assert.equal(source.accounting.journalId, e.id);assert.equal(out.accounting.eventId, e.id);assert.equal(incoming.accounting.eventId, e.id);
  assert.equal(docs.legacyLedger.data().accounting.journalId, e.id);
  assert.deepEqual((await db.doc(f.paths.repBalance).get()).data().amount, 68.754);
  assert.deepEqual((await db.doc(f.paths.companyBalance).get()).data().amount, 51.579);
  const sizes = await counts(f);
  assert.equal(sizes.settlements, 2);assert.equal(sizes.cash_movements, 4);assert.equal(sizes.financial_ledger_entries, 2);
  for (const name of ["journal_entries", "events", "source_keys", "request_keys", "audit_events", "outbox", "posting_contracts", "posting_lanes"]) assert.equal(sizes[name], 1, name);
});

test("actual SDK commit witnesses are preserved independently from business dates and recorded server transforms", async () => {
  const f = await fixture(), e = await f.review(), r = await f.persist({}, e), paths = accountingPaths(f, e, r);
  const source = await db.doc(paths.settlement).get(), journal = await db.doc(paths.journal).get();
  assert.deepEqual(r.commit.committedAt, time(source.createTime));assert.deepEqual(r.commit.committedAt, time(journal.createTime));
  assert.deepEqual(r.commit.sourceRecordedAt, time(source.data().postedAt));
  assert.deepEqual(r.commit.journalRecordedAt, time(journal.data().recordedAt));
  assert.deepEqual(time(journal.data().accountingDate), time(date));
  assert.notDeepEqual(r.commit.committedAt, time(date));
  for (const [name, path] of Object.entries(paths)) {
    if (name === "lane" || name === "seal") continue;
    const snapshot = await db.doc(path).get();
    assert.deepEqual(time(snapshot.createTime), r.commit.committedAt, name);
    assert.deepEqual(time(snapshot.updateTime), r.commit.committedAt, name);
  }
  for (const path of [f.paths.repBalance, f.paths.companyBalance, paths.lane]) assert.deepEqual(time((await db.doc(path).get()).updateTime), r.commit.committedAt);
  const book = await db.doc(f.paths.book).get();
  assert.deepEqual(time(book.updateTime), r.commit.committedAt);
  assert.equal(book.data().settlementPostingContract.path, paths.seal);
  assert.equal(book.data().settlementPostingContract.digest, docsDigest(await db.doc(paths.seal).get()));
  assert.equal(e.timestamps.sourceCommittedAt, null);assert.equal(e.timestamps.journalCommittedAt, null);
  assert.equal((await db.doc(paths.event).get()).data().pendingEvidence.timestamps.journalCommittedAt, null);
});

function docsDigest(snapshot) {return snapshot.data().recordDigest;}

test("identical committed retries recover the original durable result and metadata without any additional writes", async () => {
  const f = await fixture(), e = await f.review(), first = await f.persist({}, e), before = await financialSnapshot(f);
  for (const expected of [e, clone(e), undefined]) {
    const r = await f.persist({}, expected);
    assert.equal(r.recovered, true);assert.deepEqual(r.result, first.result);assert.deepEqual(r.commit, first.commit);
  }
  assert.deepEqual(await financialSnapshot(f), before);
});

test("concurrent same-key requests all recover one original journal and cash pair", async () => {
  const f = await fixture(), e = await f.review(), results = await Promise.all(Array.from({length: 4}, () => f.persist({}, e)));
  assert.equal(results.filter(r => !r.recovered).length, 1);
  for (const r of results) {assert.deepEqual(r.result, results[0].result);assert.deepEqual(r.commit, results[0].commit);}
  const size = await counts(f);assert.equal(size.journal_entries, 1);assert.equal(size.cash_movements, 4);
  assert.equal((await db.doc(f.paths.repBalance).get()).data().amount, 68.754);
});

test("concurrent different sources cannot consume reviewed positions twice and can explicitly re-prepare the losing request", async () => {
  const f = await fixture(), first = await f.review(), otherInput = {idempotencyKey: "different-atomic-key"}, second = await f.review(otherInput);
  const outcomes = await Promise.allSettled([f.persist({}, first), f.persist(otherInput, second)]);
  assert.equal(outcomes.filter(r => r.status === "fulfilled").length, 1);
  const loser = outcomes.findIndex(r => r.status === "rejected");assert.equal(outcomes[loser].reason.code, "failed-precondition", outcomes[loser].reason.stack);
  assert.equal((await counts(f)).journal_entries, 1);
  const overrides = loser === 0 ? {} : otherInput, renewed = await f.review(overrides);
  await f.persist(overrides, renewed);
  const size = await counts(f);assert.equal(size.journal_entries, 2);assert.equal(size.cash_movements, 6);
  assert.equal((await db.doc(f.paths.repBalance).get()).data().amount, 67.52);
  assert.equal((await db.doc(f.paths.companyBalance).get()).data().amount, 52.813);
});

test("one pinned lane serializes complete event hashes while older committed results remain recoverable", async () => {
  const f = await fixture();await db.doc(f.paths.book).update({postingLaneCount: 1});
  const firstEvidence = await f.review(), first = await f.persist({}, firstEvidence);
  const secondInput = {idempotencyKey: "second-same-lane-key"}, secondEvidence = await f.review(secondInput), second = await f.persist(secondInput, secondEvidence);
  assert.equal(first.result.laneId, "lane_00");assert.equal(second.result.laneId, "lane_00");
  assert.equal(first.result.laneSequence, 1);assert.equal(second.result.laneSequence, 2);
  const firstEvent = (await db.doc(firstEvidence.targets.event).get()).data(), secondEvent = (await db.doc(secondEvidence.targets.event).get()).data();
  assert.equal(secondEvent.lane.previousEventId, first.result.eventId);assert.equal(secondEvent.lane.previousEventHash, firstEvent.eventHash);
  const lane = db.doc(`${f.b}/posting_lanes/lane_00`), head = await lane.get();
  assert.equal(head.data().sequence, 2);assert.equal(head.data().lastEventId, second.result.eventId);assert.equal(head.data().lastEventHash, secondEvent.eventHash);
  assert.deepEqual(time(head.updateTime), second.commit.committedAt);
  assert.deepEqual((await f.persist({}, firstEvidence)).result, first.result);
  // Deliberately corrupt this synthetic mutable head, never repair posted history.
  await lane.update({lastEventHash: "0".repeat(64)});
  const thirdInput = {idempotencyKey: "third-same-lane-key"}, thirdEvidence = await f.review(thirdInput), before = await financialSnapshot(f);
  await assert.rejects(() => f.persist(thirdInput, thirdEvidence), error => {assert.ok(["failed-precondition", "data-loss"].includes(error.code), error.stack);return true;});
  assert.deepEqual(await financialSnapshot(f), before);
});

for (const [name, change] of [["amount", {amount: "2.345"}], ["date", {settlementDate: {seconds: date.seconds + 1, nanoseconds: date.nanoseconds}}],
  ["nanoseconds", {settlementDate: {seconds: date.seconds, nanoseconds: date.nanoseconds + 1000}}], ["notes", {notes: "Conflicting notes"}],
  ["representative", {salesRepId: "another-valid-identifier"}]]) test(`committed request rejects conflicting ${name}`, async () => {
  const f = await fixture(), e = await f.review();await f.persist({}, e);const before = await financialSnapshot(f);
  await assert.rejects(() => f.persist(change, e), errorCode("already-exists"));
  assert.deepEqual(await financialSnapshot(f), before);
});

test("another approved admin cannot reuse an actor-scoped request or reattribute the original source", async () => {
  const f = await fixture(), e = await f.review();await f.persist({}, e);const other = `${f.company}-another-admin`;
  await db.doc(`users/${other}`).create({uid: other, companyId: f.company, role: "admin", name: "Other synthetic admin", active: true, approvalStatus: "approved"});
  const before = await financialSnapshot(f);
  await assert.rejects(() => f.persist({}, e, other), errorCode("already-exists"));assert.deepEqual(await financialSnapshot(f), before);
});

test("committed recovery precedes current cash, period, mapping and representative eligibility checks", async () => {
  const f = await fixture(), e = await f.review(), original = await f.persist({}, e);
  await f.advance();await db.doc(f.paths.period).update({status: "closed"});
  await db.doc(f.paths.repAccount).update({active: false});await db.doc(`users/${f.rep}`).update({active: false});
  await db.doc(f.paths.book).update({settlementJournalEmulatorEnabled: false});
  const before = await financialSnapshot(f), recovered = await f.persist({}, e);
  assert.equal(recovered.recovered, true);assert.deepEqual(recovered.result, original.result);assert.deepEqual(recovered.commit, original.commit);
  assert.deepEqual(await financialSnapshot(f), before);
});

test("the original source binding recovers its book after the active company book changes", async () => {
  const f = await fixture(), e = await f.review(), first = await f.persist({}, e);
  await db.doc(f.paths.company).update({activeBookId: "another-book-with-no-accounting-configuration"});
  const before = await financialSnapshot(f), replay = await f.persist({}, e);
  assert.equal(replay.recovered, true);assert.deepEqual(replay.result, first.result);assert.deepEqual(replay.commit, first.commit);
  assert.deepEqual(await financialSnapshot(f), before);
});

test("committed recovery rejects forged supplied evidence rather than bypassing its comparison", async () => {
  const f = await fixture(), e = await f.review();await f.persist({}, e);const forged = clone(e), before = await financialSnapshot(f);
  forged.economics.lines[0].debitUnits = "1";
  await assert.rejects(() => f.persist({}, forged), error => {assert.ok(["invalid-argument", "failed-precondition", "already-exists"].includes(error.code), error.stack);return true;});
  assert.deepEqual(await financialSnapshot(f), before);
});

test("recovery still requires current authenticated company admin authority", async () => {
  const f = await fixture(), e = await f.review();await f.persist({}, e);const before = await financialSnapshot(f);
  await assert.rejects(() => persist(db, undefined, f.input, e, enabled), errorCode("unauthenticated"));
  await assert.rejects(() => f.persist({salesRepId: "another-holder-identifier"}, e, f.rep), errorCode("permission-denied"));
  await db.doc(`users/${f.admin}`).update({active: false});
  await assert.rejects(() => f.persist({}, e), errorCode("permission-denied"));assert.deepEqual(await financialSnapshot(f), before);
});

test("the default capability is disabled and only the dedicated synthetic project/loopback runtime can persist", async () => {
  const f = await fixture(), e = await f.review(), before = await financialSnapshot(f);
  await assert.rejects(() => persist(db, f.admin, f.input, e), errorCode("failed-precondition"));
  await assert.rejects(() => f.persist({}, e, f.admin, db, {enableEmulatorPersistence: false}), errorCode("failed-precondition"));
  const nonapproved = wrapped((callback, options) => db.runTransaction(callback, options), {projectId: "synthetic-unapproved-project"});
  await assert.rejects(() => f.persist({}, e, f.admin, nonapproved), errorCode("failed-precondition"));
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  try {delete process.env.FIRESTORE_EMULATOR_HOST;await assert.rejects(() => f.persist({}, e), errorCode("failed-precondition"));}
  finally {process.env.FIRESTORE_EMULATOR_HOST = host;}
  assert.deepEqual(await financialSnapshot(f), before);
});

test("a claimed emulator environment cannot override a mismatched resolved SDK transport or database", async () => {
  const f = await fixture(), e = await f.review(), before = await financialSnapshot(f), settings = Reflect.get(db, "_settings");
  for (const extra of [{_settings: {...settings, servicePath: "synthetic-remote.invalid"}}, {_settings: {...settings, ssl: true}},
    {_settings: {...settings, port: settings.port + 1}}, {databaseId: "synthetic-nondefault-database"}]) {
    const invalid = wrapped(() => {assert.fail("transport gate must reject before opening a transaction");}, extra);
    await assert.rejects(() => f.persist({}, e, f.admin, invalid), errorCode("failed-precondition"));
  }
  assert.deepEqual(await financialSnapshot(f), before);
});

test("caller-owned composition rejects a transaction from another resolved transport before any reads", async () => {
  const f = await fixture(), e = await f.review(), before = await financialSnapshot(f);
  const wrong = wrapped(() => assert.fail("mismatched transaction must not execute"),
    {_settings: {...Reflect.get(db, "_settings"), servicePath: "synthetic-remote.invalid"}});
  const transaction = {_firestore: wrong, get() {assert.fail("no mismatched-client reads");}, getAll() {assert.fail("no mismatched-client reads");}};
  await assert.rejects(() => compose(transaction, db, f.admin, f.input, e, enabled), errorCode("failed-precondition"));
  assert.deepEqual(await financialSnapshot(f), before);
});

for (const [name, change] of [["disabled book capability", {settlementJournalEmulatorEnabled: false}],
  ["missing lane count", {postingLaneCount: FieldValue.delete()}], ["zero lane count", {postingLaneCount: 0}],
  ["unsupported lane schema", {postingLaneSchemaVersion: 2}], ["missing journal definition", {settlementJournalDefinitionId: FieldValue.delete()}],
  ["unpinned journal revision", {settlementJournalDefinitionRevisionId: "unapproved-revision"}]]) {
  test(`freshly reviewed evidence cannot bypass ${name}`, async () => {
    const f = await fixture();await db.doc(f.paths.book).update(change);
    const e = await f.review(), before = await financialSnapshot(f);
    await assert.rejects(() => f.persist({}, e), errorCode("failed-precondition"));assert.deepEqual(await financialSnapshot(f), before);
  });
}

test("fresh posting requires reviewed pending evidence and never silently regenerates stale review", async () => {
  const f = await fixture(), before = await financialSnapshot(f);
  await assert.rejects(() => f.persist(), errorCode("invalid-argument"));
  const e = await f.review();await f.advance();const advanced = await financialSnapshot(f);
  await assert.rejects(() => f.persist({}, e), errorCode("failed-precondition"));assert.deepEqual(await financialSnapshot(f), advanced);
  assert.equal((await counts(f)).journal_entries, 0);assert.equal(before.length + 4, advanced.length);
});

test("unpersistable sub-microsecond business timestamps reject before any atomic write", async () => {
  const f = await fixture(), overrides = {settlementDate: {seconds: date.seconds, nanoseconds: 123456789}};
  const e = await f.review(overrides), before = await financialSnapshot(f);
  await assert.rejects(() => f.persist(overrides, e), error => {assert.ok(["invalid-argument", "failed-precondition"].includes(error.code), error.stack);return true;});
  assert.deepEqual(await financialSnapshot(f), before);
});

for (const [amount, repAfter, companyAfter] of [["0.001", 69.987, 50.346], ["69.988", 0, 120.333]]) {
  test(`exact ${amount} settlement balances and replays even at zero remaining cash`, async () => {
    const f = await fixture(), overrides = {amount}, e = await f.review(overrides), first = await f.persist(overrides, e);
    const before = await financialSnapshot(f), recovered = await f.persist(overrides, e);
    assert.equal(recovered.recovered, true);assert.deepEqual(recovered.result, first.result);
    assert.equal((await db.doc(f.paths.repBalance).get()).data().amount, repAfter);
    assert.equal((await db.doc(f.paths.companyBalance).get()).data().amount, companyAfter);
    assert.deepEqual(await financialSnapshot(f), before);
  });
}

for (const [name, mutate] of [["debit", e => {e.economics.lines[0].debitUnits = "1";}], ["credit", e => {e.economics.lines[1].creditUnits = "1";}],
  ["account", e => {e.economics.lines[0].account.accountId = "forged-account";}], ["holder", e => {e.cashEffects[0].holderUid = e.source.actor.uid;}],
  ["currency", e => {e.economics.currency = "USD";}], ["future commit timestamp", e => {e.timestamps.journalCommittedAt = time(date);}],
  ["target path", e => {e.targets.journal = "companies/foreign/journal_entries/forged";}], ["unknown approval", e => {e.approved = true;}]]) {
  test(`forged ${name} cannot write any settlement or journal`, async () => {
    const f = await fixture(), e = clone(await f.review()), before = await financialSnapshot(f);mutate(e);
    await assert.rejects(() => f.persist({}, e), errorCode("invalid-argument"));assert.deepEqual(await financialSnapshot(f), before);
  });
}

const gateFailures = [
  ["book capability absent", "book", {settlementJournalEmulatorEnabled: FieldValue.delete()}],
  ["live journal flag", "book", {journalPostingEnabled: true}], ["inactive company", "company", {active: false}],
  ["closed period", "period", {status: "closed"}], ["active cash lock", "lock", {active: true}],
  ["unapproved mapping", "mapping", {approvalStatus: "pending"}], ["foreign mapping", "mapping", {companyId: "foreign"}],
  ["unpinned cash account", "repAccount", {revisionId: "unreviewed"}], ["stale balance", "repBalance", {amount: 69.989}],
  ["journal definition missing", "definition", null], ["unapproved journal", "definition", {approvalStatus: "pending"}],
  ["inactive journal", "definition", {active: false}], ["foreign journal", "definition", {companyId: "foreign"}],
  ["wrong-book journal", "definition", {bookId: "foreign-book"}], ["journal revision", "definition", {revisionId: "journal-v2"}],
  ["journal action", "definition", {action: "invoice"}], ["journal currency", "definition", {currency: "USD"}],
  ["journal numbering policy", "definition", {numberingPolicy: "unapproved-default"}],
  ["lane count absent", "book", {postingLaneCount: FieldValue.delete()}], ["invalid lane count", "book", {postingLaneCount: 0}],
  ["unsupported lane schema", "book", {postingLaneSchemaVersion: 2}],
];
for (const [name, target, change] of gateFailures) test(`atomic gate blocks ${name} without partial financial writes`, async () => {
  const f = await fixture(), e = await f.review(), ref = db.doc(f.paths[target]);
  if (change === null) await ref.delete();else await ref.set(change, {merge: true});
  const before = await financialSnapshot(f);await assert.rejects(() => f.persist({}, e), error => {
    assert.ok((target === "definition" ? ["failed-precondition", "data-loss"] : ["failed-precondition"]).includes(error.code), error.stack);return true;
  });
  assert.deepEqual(await financialSnapshot(f), before);
});

test("the durable monetary/lane contract cannot change to a new lane count after its first posting", async () => {
  const f = await fixture(), e = await f.review();await f.persist({}, e);
  await db.doc(f.paths.book).update({postingLaneCount: 8});
  const overrides = {idempotencyKey: "after-lane-schema-change"}, reviewed = await f.review(overrides), before = await financialSnapshot(f);
  await assert.rejects(() => f.persist(overrides, reviewed), error => {assert.ok(["failed-precondition", "data-loss"].includes(error.code), error.stack);return true;});
  assert.deepEqual(await financialSnapshot(f), before);
});

test("an initialized book cannot treat a missing seal as a first posting on a different empty lane", async () => {
  const f = await fixture(), first = await f.persist({}, await f.review());let overrides, reviewed, lane;
  for (let i = 0; i < 32; i++) {
    const candidate = {idempotencyKey: `missing-seal-new-lane-${i}`}, e = await f.review(candidate);
    const id = `lane_${(parseInt(evidenceDigest(e.id).slice(0, 8), 16) % 4).toString().padStart(2, "0")}`;
    if (id !== first.result.laneId) {overrides = candidate;reviewed = e;lane = id;break;}
  }
  assert.ok(reviewed);assert.equal((await db.doc(`${f.b}/posting_lanes/${lane}`).get()).exists, false);
  assert.ok((await db.doc(f.paths.book).get()).data().settlementPostingContract);
  const before = await financialSnapshot(f);
  const missing = snapshot => snapshot.ref.path !== f.paths.seal ? snapshot : new Proxy(snapshot, {get(target, key) {
    if (key === "exists") return false;if (key === "createTime" || key === "updateTime") return undefined;if (key === "data") return () => undefined;
    const value = Reflect.get(target, key, target);return typeof value === "function" ? value.bind(target) : value;
  }});
  const database = wrapped((callback, options) => db.runTransaction(t => callback(proxyTransaction(t, {
    get: async ref => missing(await t.get(ref)), getAll: async (...refs) => (await t.getAll(...refs)).map(missing),
    create() {assert.fail("missing seal must block before any create");}, set() {assert.fail("missing seal must block before any set");},
    update() {assert.fail("missing seal must block before any update");}, delete() {assert.fail("missing seal must block before any delete");},
  })), options));
  await assert.rejects(() => f.persist(overrides, reviewed, f.admin, database), error => {
    assert.ok(["failed-precondition", "data-loss"].includes(error.code), error.stack);assert.match(error.message, /posting contract/i);return true;
  });
  assert.deepEqual(await financialSnapshot(f), before);
});

test("an approved-looking new currency configuration cannot reinterpret an already sealed book", async () => {
  const f = await fixture(), e = await f.review();await f.persist({}, e);
  const scoped = (id, extra) => ({id, companyId: f.company, bookId: f.bookId, revisionId: id, approvalStatus: "approved", ...extra});
  const batch = db.batch();
  batch.create(db.doc(`${f.b}/policy_revisions/policy-usd-v1`), scoped("policy-usd-v1", {currency: "USD", moneyScale: 3,
    accountingDateBasis: "settlement_business_date", legacyCurrencyBindingId: "binding-usd-v1"}));
  batch.create(db.doc(`${f.b}/currency_bindings/binding-usd-v1`), scoped("binding-usd-v1", {currency: "USD", moneyScale: 3,
    sourceCollection: "settlements", postingSource: "recordCashSettlement", settlementMetadataVersion: 1}));
  for (const id of ["company-usd-control", "rep-usd-control"]) batch.create(db.doc(`${f.b}/chart_accounts/${id}`), scoped(id,
    {currency: "USD", moneyScale: 3, accountType: "asset", control: "cash", active: true, postingAllowed: true, requiresTreasuryDimension: true}));
  batch.create(db.doc(`${f.b}/settlement_mappings/mapping-usd-v1`), scoped("mapping-usd-v1", {companyCashAccountId: "company-usd-control",
    companyCashAccountRevisionId: "company-usd-control", representativeCashAccountId: "rep-usd-control", representativeCashAccountRevisionId: "rep-usd-control"}));
  batch.create(db.doc(`${f.b}/journal_definitions/settlement-usd-journal`), scoped("settlement-usd-journal", {revisionId: "usd-journal-v1", active: true,
    action: "rep_to_company_cash", currency: "USD", moneyScale: 3, numberingPolicy: "source_identity"}));
  batch.update(db.doc(f.paths.book), {revisionId: "book-v2", currency: "USD", policyRevisionId: "policy-usd-v1",
    settlementMappingRevisionId: "mapping-usd-v1", settlementJournalDefinitionId: "settlement-usd-journal", settlementJournalDefinitionRevisionId: "usd-journal-v1"});
  await batch.commit();
  const overrides = {idempotencyKey: "after-currency-change"}, reviewed = await f.review(overrides), before = await financialSnapshot(f);
  assert.equal(reviewed.economics.currency, "USD");
  await assert.rejects(() => f.persist(overrides, reviewed), error => {
    assert.ok(["failed-precondition", "data-loss"].includes(error.code), error.stack);assert.match(error.message, /book monetary\/lane contract/i);return true;
  });
  assert.deepEqual(await financialSnapshot(f), before);
});

test("cross-company users and evidence cannot gain access to another company account", async () => {
  const f = await fixture(), other = await fixture(), e = await f.review(), before = await financialSnapshot(f);
  await assert.rejects(() => f.persist({}, e, other.admin), errorCode("permission-denied"));
  await assert.rejects(() => other.persist({}, e), errorCode("already-exists"));
  assert.deepEqual(await financialSnapshot(f), before);assert.equal((await counts(other)).journal_entries, 0);
});

test("pre-existing legacy settlement is not silently journaled or backfilled and legacy replay remains unchanged", async () => {
  const f = await fixture(), e = await f.review();
  await legacyPost(db, f.admin, f.company, f.input.idempotencyKey, {salesRepId: f.rep, amount: 1.234, settlementDate: date, notes: f.input.notes});
  const before = await financialSnapshot(f);
  await assert.rejects(() => f.persist({}, e), error => {assert.ok(["already-exists", "failed-precondition"].includes(error.code));return true;});
  assert.equal((await legacyPost(db, f.admin, f.company, f.input.idempotencyKey,
    {salesRepId: f.rep, amount: 1.234, settlementDate: new Timestamp(date.seconds + 1, 0), notes: "Legacy replay is preserved"})).alreadyPosted, true);
  assert.deepEqual(await financialSnapshot(f), before);assert.equal((await counts(f)).journal_entries, 0);
});

for (const n of [1, 3, 5, 9, 13]) test(`failure after queued write ${n} rolls back the entire cash/journal envelope`, async () => {
  const f = await fixture(), e = await f.review(), before = await financialSnapshot(f);let queued = 0;
  const database = wrapped((callback, options) => db.runTransaction(t => callback(proxyTransaction(t, Object.fromEntries(
    ["create", "set", "update", "delete"].map(method => [method, (...args) => {
      const result = t[method](...args);if (++queued === n) throw new Error(`synthetic failure after write ${n}`);return result;
    }])))), options));
  await assert.rejects(() => f.persist({}, e, f.admin, database), /synthetic failure after write/);
  assert.equal(queued, n);assert.deepEqual(await financialSnapshot(f), before);
});

test("all reads precede writes and every immutable target uses create preconditions", async t => {
  const f = await fixture(), e = await f.review(), attempts = [];
  const database = wrapped((callback, options) => db.runTransaction(async t => {
    const attempt = {reads: 0, writes: []};attempts.push(attempt);
    const overrides = {
      get(ref) {assert.equal(attempt.writes.length, 0, "read after write");assert.equal(typeof ref.path, "string", "query forbidden");attempt.reads++;return t.get(ref);},
      getAll(...refs) {assert.equal(attempt.writes.length, 0, "read after write");for (const ref of refs) assert.equal(typeof ref.path, "string", "query forbidden");attempt.reads += refs.length;return t.getAll(...refs);},
    };
    for (const method of ["create", "set", "update", "delete"]) overrides[method] = (...args) => {attempt.writes.push({method, path: args[0].path});return t[method](...args);};
    return callback(proxyTransaction(t, overrides));
  }, options));
  const r = await f.persist({}, e, f.admin, database), mutating = attempts.filter(a => a.writes.length);
  assert.equal(mutating.length, 1);assert.ok(mutating[0].reads <= 48);assert.equal(mutating[0].writes.length, 15);
  t.diagnostic(`Fresh atomic transaction: ${mutating[0].reads} document reads, ${mutating[0].writes.length} writes, zero queries.`);
  const paths = accountingPaths(f, e, r), immutable = Object.entries(paths).filter(([name]) => !["lane", "seal"].includes(name));
  for (const [, path] of immutable) assert.deepEqual(mutating[0].writes.filter(w => w.path === path).map(w => w.method), ["create"]);
  assert.ok(mutating[0].writes.every(w => w.method !== "delete"));
});

test("SDK callback retry queues no partial effects and eventually produces one durable result", async () => {
  const f = await fixture(), e = await f.review();let aborted = false, mutatingAttempts = 0;
  const database = wrapped((callback, options) => db.runTransaction(async t => {
    let writes = 0;const overrides = {};
    for (const method of ["create", "set", "update", "delete"]) overrides[method] = (...args) => {writes++;return t[method](...args);};
    const value = await callback(proxyTransaction(t, overrides));
    if (writes) {mutatingAttempts++;if (!aborted) {aborted = true;throw Object.assign(new Error("synthetic retry"), {code: 10});}}
    return value;
  }, options));
  const result = await f.persist({}, e, f.admin, database);
  assert.equal(mutatingAttempts, 2);assert.equal(result.recovered, false);assert.equal((await counts(f)).journal_entries, 1);
  assert.equal((await db.doc(f.paths.repBalance).get()).data().amount, 68.754);
});

test("only the emulator's exact closed-transaction document-read error is retried as a fresh bounded attempt", async () => {
  const f = await fixture(), e = await f.review();let injected = false, attempts = 0;
  const database = wrapped((callback, options) => db.runTransaction(t => {
    attempts++;
    return callback(proxyTransaction(t, {getAll(...refs) {
      if (!injected) {injected = true;throw Object.assign(new Error("3 INVALID_ARGUMENT: Transaction is invalid or closed."),
        {code: 3, details: "Transaction is invalid or closed."});}
      return t.getAll(...refs);
    }}));
  }, options));
  const result = await f.persist({}, e, f.admin, database);
  assert.equal(result.recovered, false);assert.ok(attempts >= 3);assert.equal((await counts(f)).journal_entries, 1);
  assert.equal((await db.doc(f.paths.repBalance).get()).data().amount, 68.754);
});

test("unrelated INVALID_ARGUMENT document-read errors remain fatal and never get blindly retried", async () => {
  const f = await fixture(), e = await f.review(), before = await financialSnapshot(f);let attempts = 0;
  const database = wrapped((callback, options) => db.runTransaction(t => {
    attempts++;
    return callback(proxyTransaction(t, {getAll() {throw Object.assign(new Error("3 INVALID_ARGUMENT: Unrelated synthetic invalid argument."),
      {code: 3, details: "Unrelated synthetic invalid argument."});}}));
  }, options));
  await assert.rejects(() => f.persist({}, e, f.admin, database), error => {assert.equal(error.code, 3);assert.match(error.message, /Unrelated synthetic/);return true;});
  assert.equal(attempts, 1);assert.deepEqual(await financialSnapshot(f), before);
});

test("a shared approved cash control keeps separate treasury dimensions in durable posting and recovery", async () => {
  const f = await fixture();
  await db.doc(f.paths.mapping).update({representativeCashAccountId: "company-control", representativeCashAccountRevisionId: "company-account-v1"});
  const e = await f.review(), posted = await f.persist({}, e), journal = (await db.doc(e.targets.journal).get()).data();
  assert.equal(journal.lines[0].account.accountId, journal.lines[1].account.accountId);
  assert.notEqual(journal.lines[0].account.treasuryAccountId, journal.lines[1].account.treasuryAccountId);
  assert.deepEqual(journal.lines.map(line => line.account.holderUid), [f.company, f.rep]);
  const before = await financialSnapshot(f), recovered = await f.persist({}, e);
  assert.equal(recovered.recovered, true);assert.deepEqual(recovered.result, posted.result);assert.deepEqual(await financialSnapshot(f), before);
});

test("lost acknowledgement after a real commit recovers original result without duplicating cash", async () => {
  const f = await fixture(), e = await f.review();let lost = false;
  const database = wrapped(async (callback, options) => {
    let wrote = false;
    const result = await db.runTransaction(t => {
      const overrides = {};
      for (const method of ["create", "set", "update", "delete"]) overrides[method] = (...args) => {wrote = true;return t[method](...args);};
      return callback(proxyTransaction(t, overrides));
    }, options);
    if (wrote && !lost) {lost = true;throw new Error("synthetic lost acknowledgement after commit");}return result;
  });
  await assert.rejects(() => f.persist({}, e, f.admin, database), /lost acknowledgement/);
  const before = await financialSnapshot(f), recovered = await f.persist({}, e);
  assert.equal(recovered.recovered, true);assert.deepEqual(await financialSnapshot(f), before);
  assert.equal((await counts(f)).journal_entries, 1);assert.equal((await counts(f)).cash_movements, 4);
});

test("post-commit observation failure remains recoverable and never causes compensating or duplicate posting", async () => {
  const f = await fixture(), e = await f.review();let transactions = 0;
  const database = wrapped((callback, options) => {
    if (++transactions === 2) throw new Error("synthetic unavailable commit observation");return db.runTransaction(callback, options);
  });
  await assert.rejects(() => f.persist({}, e, f.admin, database), /unavailable commit observation/);
  const before = await financialSnapshot(f), recovered = await f.persist({}, e);
  assert.equal(recovered.recovered, true);assert.deepEqual(await financialSnapshot(f), before);
});

test("a cash change between SDK attempts invalidates the reviewed pending envelope", async () => {
  const f = await fixture(), e = await f.review();let advance, first = true;
  const database = wrapped((callback, options) => db.runTransaction(async t => {
    if (advance) await advance;const result = await callback(t);
    if (first) {first = false;advance = f.advance();throw Object.assign(new Error("synthetic contention"), {code: 10});}return result;
  }, options));
  await assert.rejects(() => f.persist({}, e, f.admin, database), errorCode("failed-precondition"));
  assert.equal((await counts(f)).journal_entries, 0);assert.equal((await counts(f)).settlements, 2);
  assert.equal((await db.doc(f.paths.repBalance).get()).data().amount, 68.988);
});

for (const target of ["repMovement", "companyMovement", "legacyLedger", "sourceKey", "journal", "event"]) {
  test(`existing ${target} target blocks new atomic posting instead of overwriting a collision`, async () => {
    const f = await fixture(), e = await f.review();await db.doc(e.targets[target]).create({syntheticCollision: true});
    const before = await financialSnapshot(f);
    await assert.rejects(() => f.persist({}, e), error => {assert.ok(["already-exists", "failed-precondition", "data-loss"].includes(error.code), error.stack);return true;});
    assert.deepEqual(await financialSnapshot(f), before);
  });
}

for (const target of ["settlement", "repMovement", "companyMovement", "legacyLedger", "sourceKey", "journal", "event", "request", "audit", "outbox"]) {
  test(`committed recovery rejects altered immutable ${target} without repairing financial history`, async () => {
    const f = await fixture(), e = await f.review(), r = await f.persist({}, e), paths = accountingPaths(f, e, r);
    await db.doc(paths[target]).update({syntheticTamper: true});const before = await financialSnapshot(f);
    await assert.rejects(() => f.persist({}, e), error => {assert.ok(["failed-precondition", "data-loss", "already-exists"].includes(error.code), error.stack);return true;});
    assert.deepEqual(await financialSnapshot(f), before);
  });
}

for (const target of ["sourceKey", "journal", "request", "audit", "outbox"]) {
  test(`missing committed ${target} evidence blocks recovery without any reconstruction`, async () => {
    const f = await fixture(), e = await f.review(), r = await f.persist({}, e), missingPath = accountingPaths(f, e, r)[target];
    const before = await financialSnapshot(f);
    const absent = snapshot => snapshot.ref.path !== missingPath ? snapshot : new Proxy(snapshot, {get(object, key) {
      if (key === "exists") return false;
      if (key === "createTime" || key === "updateTime") return undefined;
      if (key === "data") return () => undefined;
      const value = Reflect.get(object, key, object);return typeof value === "function" ? value.bind(object) : value;
    }});
    const database = wrapped((callback, options) => db.runTransaction(t => callback(proxyTransaction(t, {
      get: async ref => absent(await t.get(ref)), getAll: async (...refs) => (await t.getAll(...refs)).map(absent),
    })), options));
    await assert.rejects(() => f.persist({}, e, f.admin, database), error => {assert.ok(["failed-precondition", "data-loss", "already-exists"].includes(error.code), error.stack);return true;});
    assert.deepEqual(await financialSnapshot(f), before);
  });
}

test("pure committed intent, historical preflight and legacy cash reporting preserve their contracts", async () => {
  const f = await fixture(), e = await f.review(), posted = await f.persist({}, e);
  const source = (await db.doc(e.targets.settlement).get()).data();
  const movements = await Promise.all([e.targets.repMovement, e.targets.companyMovement].map(async path => (await db.doc(path).get()).data()));
  const intent = buildSettlementJournalIntent({companyId: f.company, bookId: f.bookId, policy: e.economics.policy,
    mappings: e.economics.lines.map(l => l.account), settlement: source, movements});
  assert.deepEqual(intent.lines, e.economics.lines);assert.equal(intent.id, e.id);assert.equal(intent.amountUnits, "1234");
  const historical = await committedPreflight(db, f.admin, {companyId: f.company, settlementId: "settlement_existing-cash-head-key"});
  assert.equal(historical.intent.amountUnits, "30123");
  assert.equal(posted.result.settlementId, source.id);
  const replay = await legacyPost(db, f.admin, f.company, f.input.idempotencyKey,
    {salesRepId: f.rep, amount: 1.234, settlementDate: date, notes: f.input.notes});
  assert.equal(replay.alreadyPosted, true);assert.equal((await counts(f)).journal_entries, 1);
  const index = readFileSync(join(__dirname, "../src/index.ts"), "utf8");
  assert.doesNotMatch(index, /settlement_journal_persistence|persistSettlementJournal/);
});
