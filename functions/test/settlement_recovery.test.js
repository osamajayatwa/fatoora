"use strict";
const assert = require("node:assert/strict");
const {test, after} = require("node:test");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw new Error("Recovery tests require an isolated loopback emulator.");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {recoverSettlementTransaction: recover} = require("../lib/trusted/settlement_recovery");
const {settlementEvidenceDigest: digest} = require("../lib/trusted/settlement_pending_evidence");
const {createSettlementFixture} = require("./helpers/settlement_fixture");
const {analyzeCashRecords} = require("../scripts/cash_reconciliation_common");
const app = initializeApp({projectId: "demo-fatoora-phase2b7"}, "settlement-recovery-tests"), db = getFirestore(app);
after(() => deleteApp(app));
const date = Timestamp.fromDate(new Date("2026-08-05T12:00:00Z"));
const enabled = {enableEmulatorRecovery: true};
const errorCode = code => e => {assert.equal(e.code, code, e.stack);return true;};
const time = t => ({seconds: t.seconds, nanoseconds: t.nanoseconds});
const clone = v => JSON.parse(JSON.stringify(v));
async function fixture(post = true) {
  const f = await createSettlementFixture(db, date);f.e = await f.review();
  if (post) f.first = await f.persist({}, f.e);
  f.recover = (input = {}, uid = f.admin, database = db, expected) => recover(database, uid, {...f.input, ...input}, expected, enabled);
  f.paths = {...f.paths, ...f.e.targets, ...(post ? {request: `${f.b}/request_keys/${f.first.result.requestId}`,
    audit: `${f.b}/audit_events/${f.e.id}`, outbox: `${f.b}/outbox/${f.e.id}`,
    lane: `${f.b}/posting_lanes/${f.first.result.laneId}`} : {})};
  return f;
}
async function snapshot(f) {
  const rows = [];
  for (const path of [f.c, f.b, ...Object.values(f.paths)]) {
    const s = await db.doc(path).get();rows.push({path, data: s.data(), version: s.updateTime && time(s.updateTime)});
  }
  return rows;
}
function wrapped(run, extra = {}) {
  return new Proxy(db, {get(target, prop) {
    if (Object.hasOwn(extra, prop)) return extra[prop];
    if (prop === "runTransaction") return (callback, options) => run(callback, options);
    const value = Reflect.get(target, prop, target);return typeof value === "function" ? value.bind(target) : value;
  }});
}
function proxiedTx(tx, overrides) {
  return new Proxy(tx, {get(target, prop) {const value = overrides[prop] || Reflect.get(target, prop, target);
    return typeof value === "function" ? value.bind(target) : value;}});
}

test("independent recovery reconstructs exact balanced custody and the original committed result without writes", async t => {
  const f = await fixture(), before = await snapshot(f), r = await f.recover({}, f.admin, db, f.e);
  assert.equal(r.recovered, true);assert.deepEqual(r.result, f.first.result);assert.deepEqual(r.commit, f.first.commit);
  assert.equal(r.verification.scope, "transaction");assert.equal(r.verification.historicalReconciliation, "not_performed");
  assert.equal(r.verification.debitUnits, "1234");assert.equal(r.verification.creditUnits, "1234");
  assert.equal(r.verification.totalCashBeforeUnits, "120333");assert.equal(r.verification.totalCashAfterUnits, "120333");
  assert.equal(r.observation.queryReads, 9);assert.ok(r.observation.documentReads <= 64);
  t.diagnostic(`Synthetic base recovery: ${r.observation.documentReads} unique document reads, ${r.observation.queryReads} bounded reference-only queries, zero writes.`);
  assert.deepEqual(await snapshot(f), before);
});

test("read-only SDK option and write traps prohibit financial mutations on every read path", async () => {
  const f = await fixture();let writes = 0;
  const database = wrapped((callback, options) => {
    assert.deepEqual(options, {readOnly: true});
    return db.runTransaction(t => callback(proxiedTx(t, Object.fromEntries(["create", "set", "update", "delete"].map(name =>
      [name, () => {writes++;throw new Error("WRITE ATTEMPT");}])))), options);
  });
  await f.recover({}, f.admin, database);assert.equal(writes, 0);
});

test("lost acknowledgements and concurrent recovery always return the original durable result", async () => {
  const f = await fixture(false);let committed = false;
  const database = wrapped(async (callback, options) => {
    const value = await db.runTransaction(callback, options);
    if (!committed) {committed = true;throw new Error("Synthetic lost acknowledgement");}return value;
  });
  const {persistSettlementJournalTransaction} = require("../lib/trusted/settlement_journal_persistence");
  await assert.rejects(persistSettlementJournalTransaction(database, f.admin, f.input, f.e, {enableEmulatorPersistence: true}), /lost acknowledgement/);
  const before = await snapshot(f), results = await Promise.all(Array.from({length: 5}, () => f.recover()));
  for (const r of results) {assert.deepEqual(r.result, results[0].result);assert.deepEqual(r.commit, results[0].commit);}
  assert.deepEqual(await snapshot(f), before);
});

test("transport retries reauthorize and rebuild a fresh bounded read-only attempt", async () => {
  const f = await fixture();let attempts = 0;
  const database = wrapped((callback, options) => db.runTransaction(t => callback(proxiedTx(t, {getAll: async (...refs) => {
    if (++attempts === 1) throw Object.assign(new Error("Transaction is invalid or closed."), {code: 3, details: "Transaction is invalid or closed."});
    return t.getAll(...refs);
  }})), options));
  assert.deepEqual((await f.recover({}, f.admin, database)).result, f.first.result);assert.ok(attempts > 1);
});

test("retry limit is finite and unrelated invalid-argument errors are never retried", async () => {
  const f = await fixture();
  for (const code of [10, 3, 7]) {
    let attempts = 0;const database = wrapped(async () => {attempts++;throw Object.assign(new Error("unrelated transport failure"), {code});});
    await assert.rejects(f.recover({}, f.admin, database), errorCode(code));assert.equal(attempts, code === 10 ? 5 : 1);
  }
});

test("authority revoked between read retries blocks recovery", async () => {
  const f = await fixture();let attempts = 0;
  const database = wrapped(async (callback, options) => {
    if (++attempts === 1) {await db.doc(`users/${f.admin}`).update({active: false});throw Object.assign(new Error("retry"), {code: 10});}
    return db.runTransaction(callback, options);
  });
  await assert.rejects(f.recover({}, f.admin, database), errorCode("permission-denied"));assert.equal(attempts, 2);
});

test("concurrent cash activity yields one consistent read snapshot and preserves the recovered result", async () => {
  const f = await fixture(), results = await Promise.all([f.recover(), f.advance(), f.recover()]);
  for (const r of [results[0], results[2]]) {assert.deepEqual(r.result, f.first.result);assert.deepEqual(r.commit, f.first.commit);}
});

test("shared chart control accounts retain separate treasury dimensions and deduplicated configuration reads", async () => {
  const f = await fixture(false);
  await db.doc(f.paths.mapping).update({representativeCashAccountId: "company-control", representativeCashAccountRevisionId: "company-account-v1"});
  const e = await f.review(), first = await f.persist({}, e), r = await f.recover();
  assert.deepEqual(r.result, first.result);assert.equal(r.verification.debitUnits, "1234");
});

test("equal-payload no-op writes retain the SDK witness and do not invent an overwrite finding", async () => {
  const f = await fixture(), ref = db.doc(f.paths.journal), before = await ref.get();
  await ref.set(before.data());const after = await ref.get();
  // Pinned emulator behavior: a no-op set does not change updateTime.
  assert.deepEqual(time(after.updateTime), time(before.updateTime));await f.recover();
});

test("an independent company administrator can verify the original result after the posting actor is deactivated", async () => {
  const f = await fixture(), reviewer = `${f.company}-reviewer`;
  await db.doc(`users/${reviewer}`).set({uid: reviewer, name: "Synthetic reviewer", role: "admin", companyId: f.company, active: true, approvalStatus: "approved"});
  await db.doc(`users/${f.admin}`).update({active: false});
  const r = await f.recover({}, reviewer);assert.deepEqual(r.result, f.first.result);assert.deepEqual(r.commit, f.first.commit);
  await assert.rejects(f.recover(), errorCode("permission-denied"));
});

test("historical profile display fallbacks match existing actor and representative semantics", async () => {
  const f = await fixture(false);
  await db.doc(`users/${f.admin}`).update({name: " ", email: "synthetic@example.invalid"});
  await db.doc(`users/${f.rep}`).update({name: " "});
  const e = await f.review(), first = await f.persist({}, e), r = await f.recover();
  assert.deepEqual(r.result, first.result);assert.equal(e.source.actor.name, "synthetic@example.invalid");assert.equal(e.source.salesRepName, f.rep);
});

test("old results survive later cash, lane advancement, book switch, closed period and inactive representative/accounts", async () => {
  const f = await fixture();await f.advance();
  // Force a later posting onto the same deterministic lane.
  for (let index = 0; index < 64; index++) {
    const input = {idempotencyKey: `later-key-${index}`}, e = await f.review(input);
    const lane = `lane_${(parseInt(digest(e.id).slice(0, 8), 16) % 4).toString().padStart(2, "0")}`;
    if (lane === f.first.result.laneId) {await f.persist(input, e);break;}
    assert.ok(index < 63);
  }
  const batch = db.batch();batch.update(db.doc(f.c), {activeBookId: "later-book"});
  batch.update(db.doc(`users/${f.rep}`), {active: false});batch.update(db.doc(f.paths.period), {status: "closed"});
  for (const p of [f.paths.repAccount, f.paths.companyAccount]) batch.update(db.doc(p), {active: false, postingAllowed: false});
  await batch.commit();const before = await snapshot(f), r = await f.recover();
  assert.deepEqual(r.result, f.first.result);assert.deepEqual(r.commit, f.first.commit);
  assert.ok(r.verification.configurationVersions.some(v => v.state === "changed_since_posting"));
  assert.deepEqual(await snapshot(f), before);
});

for (const key of ["settlement", "repMovement", "companyMovement", "legacyLedger", "journal", "event", "sourceKey", "request", "audit", "outbox", "seal", "definition", "lane", "repHead", "companyHead", "repBalance", "companyBalance", "policy", "mapping", "binding"]) {
  test(`missing ${key} fails closed without repair`, async () => {
    const f = await fixture();await db.doc(f.paths[key]).delete();const before = await snapshot(f);
    await assert.rejects(f.recover());assert.deepEqual(await snapshot(f), before);
  });
}
for (const key of ["settlement", "repMovement", "companyMovement", "legacyLedger", "journal", "event", "sourceKey", "request", "audit", "outbox", "seal", "definition", "repHead", "companyHead"]) {
  test(`overwritten ${key} fails immutable SDK evidence`, async () => {
    const f = await fixture(), ref = db.doc(f.paths[key]);await ref.update({syntheticCorruption: true});
    await assert.rejects(f.recover());
  });
}
for (const [key, patch] of [
  ["repBalance", {amount: 0}], ["companyBalance", {companyId: "other-company"}],
  ["repBalance", {lastMovementId: "missing-head"}], ["repBalance", {holderUid: "other-rep"}],
  ["companyBalance", {updatedAt: date}], ["lane", {sequence: 0}], ["lane", {lastEventHash: "0".repeat(64)}],
  ["book", {settlementPostingContract: FieldValue.delete()}],
]) {
  test(`corrupt current ${key} ${Object.keys(patch)[0]} fails closed`, async () => {
    const f = await fixture();await db.doc(f.paths[key]).update(patch);await assert.rejects(f.recover());
  });
}
for (const key of ["repMovement", "companyMovement", "legacyLedger", "journal", "event", "sourceKey", "request", "audit", "outbox", "settlement"]) {
  test(`duplicate linked ${key} at an alternate path is detected`, async () => {
    const f = await fixture(), ref = db.doc(f.paths[key]);await ref.parent.doc("forged-duplicate").set((await ref.get()).data());
    await assert.rejects(f.recover(), /Duplicate or partially linked/);
  });
}

for (const [label, mutate, expected] of [
  ["configuration digest", e => {e.configurationDigest = "f".repeat(64);}, /Independent configuration digest/],
  ["cross-company version", e => {e.versions[0].path = "companies/foreign-company";}, /Complete bounded version witness set/],
  ["future version", e => {e.versions[0].updateTime = {seconds: 253402300799, nanoseconds: 0};}, /Preflight version must precede/],
  ["original balance", e => {e.positions[0].amountUnits = "0";}, /Original cash position witness/],
  ["timestamp contract", e => {e.timestampContract.recordedEqualsCommit = true;}, /Pending timestamp contract/],
]) test(`forged ${label} fails independent reconstruction despite consistently rehashed outer envelopes`, async () => {
  const f = await fixture();
  // Preserve actual SDK witnesses while simulating a writer bug that commits a
  // self-consistent envelope containing a false internal preflight digest.
  const {recordDigest: ignored, recordedAt, committedAt, ...eventBase} = (await db.doc(f.paths.event).get()).data();
  eventBase.accountingDate = time(eventBase.accountingDate);
  const event = clone(eventBase);mutate(event.pendingEvidence);
  const {eventHash: oldHash, ...base} = event;event.eventHash = digest(base);
  const payloads = new Map();
  for (const key of ["event", "sourceKey", "request", "audit", "outbox"]) {
    const original = (await db.doc(f.paths[key]).get()).data();
    const {recordDigest, recordedAt: clock, committedAt: unknownClock, ...payload} = original;
    if (payload.accountingDate) payload.accountingDate = time(payload.accountingDate);
    const changed = key === "event" ? event : {...payload, eventHash: event.eventHash};
    payloads.set(f.paths[key], {...changed, recordDigest: digest(changed), recordedAt: clock, committedAt: unknownClock});
  }
  const database = wrapped((callback, options) => db.runTransaction(t => callback(proxiedTx(t, {getAll: async (...refs) =>
    (await t.getAll(...refs)).map(s => payloads.has(s.ref.path) ? new Proxy(s, {get(target, prop) {
      if (prop === "data") return () => payloads.get(s.ref.path);const value = Reflect.get(target, prop, target);return typeof value === "function" ? value.bind(target) : value;
    }}) : s)})), options));
  await assert.rejects(f.recover({}, f.admin, database), expected);
  assert.ok(ignored && recordedAt && committedAt === null && oldHash);
});

for (const [label, modify] of [
  ["inactive", f => db.doc(`users/${f.admin}`).update({active: false})],
  ["unapproved", f => db.doc(`users/${f.admin}`).update({approvalStatus: "pending"})],
  ["representative", f => db.doc(`users/${f.admin}`).update({role: "sales_rep"})],
  ["foreign company", f => db.doc(`users/${f.admin}`).update({companyId: "foreign-company"})],
  ["inactive company", f => db.doc(f.c).update({active: false})],
  ["forged profile uid", f => db.doc(`users/${f.admin}`).update({uid: "forged-admin"})],
  ["forged company scope", f => db.doc(f.c).update({companyId: "foreign-company"})],
]) test(`current authorization: ${label} fails closed`, async () => {
  const f = await fixture();await modify(f);await assert.rejects(f.recover());
});

test("unauthenticated, foreign representative, conflicting requests and forged review cannot recover", async () => {
  const f = await fixture();await assert.rejects(f.recover({}, ""), errorCode("unauthenticated"));
  await assert.rejects(f.recover({salesRepId: "another-rep"}, f.rep), errorCode("permission-denied"));
  for (const patch of [{amount: "1.235"}, {salesRepId: "another-rep"}, {notes: "changed"}, {settlementDate: {seconds: date.seconds + 1, nanoseconds: 0}}, {expectedBookId: "other-book"}]) await assert.rejects(f.recover(patch));
  const e = clone(f.e);e.economicDigest = "0".repeat(64);await assert.rejects(f.recover({}, f.admin, db, e));
});

test("missing or historical legacy-only sources never invoke a writer or backfill", async () => {
  const f = await fixture(false), before = await snapshot(f);await assert.rejects(f.recover());assert.deepEqual(await snapshot(f), before);
  await assert.rejects(f.recover({idempotencyKey: "existing-cash-head-key", amount: "30.123", notes: ""}), /Legacy settlement/);
});

test("default-off, remote client and wrong project are rejected before starting a transaction", async () => {
  const f = await fixture();let reads = 0;const database = wrapped(async () => {reads++;throw new Error("must not start");});
  await assert.rejects(recover(database, f.admin, f.input), /disabled by default/);
  await assert.rejects(f.recover({}, f.admin, wrapped(async () => {reads++;}, {_settings: {servicePath: "remote", ssl: true, port: 443}})));
  await assert.rejects(f.recover({}, f.admin, wrapped(async () => {reads++;}, {projectId: "real-project"})));
  assert.equal(reads, 0);
});

test("history clearance is explicitly separate: transaction recovery cannot certify missing unrelated cash history", async () => {
  const f = await fixture(), r = await f.recover();
  const movements = (await db.collection(`${f.c}/cash_movements`).get()).docs.map(s => ({id: s.id, data: s.data()}));
  const balances = (await db.collection(`${f.c}/cash_balances`).get()).docs.map(s => ({id: s.id, data: s.data()}));
  // Fixture has synthetic initial positions without opening movements. Local
  // settlement equations hold, but existing full-history utility flags the gap.
  const history = analyzeCashRecords({companyId: f.company, movements, balances});
  assert.ok(history.issueCount > 0);assert.equal(r.verification.historicalReconciliation, "not_performed");
});

test("adapter stays internal and has no posting, allocation or UI call site", () => {
  const root = readFileSync(join(__dirname, "../src/index.ts"), "utf8");assert.doesNotMatch(root, /settlement_recovery|recoverSettlementTransaction/);
  const code = readFileSync(join(__dirname, "../src/trusted/settlement_recovery.ts"), "utf8");
  assert.doesNotMatch(code, /FieldValue|prepareCashSettlementWrite|persistSettlementJournalTransaction|onCall|\.batch\(/);
});
