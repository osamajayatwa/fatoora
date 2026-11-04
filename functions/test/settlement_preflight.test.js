"use strict";
const assert = require("node:assert/strict");
const {test, after} = require("node:test");
const {randomUUID} = require("node:crypto");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
// Never initialize an Admin client without an isolated loopback emulator.
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) {
  throw new Error("Settlement preflight tests require a dedicated loopback Firestore emulator.");
}
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {recordCashSettlementTransaction} = require("../lib/trusted/record_cash_settlement");
const {prepareSettlementPreflight, preflightSettlementTransaction} = require("../lib/trusted/settlement_preflight");
const app = initializeApp({projectId: "demo-fatoora-phase2b5"}, "settlement-preflight-tests");
const db = getFirestore(app);
after(() => deleteApp(app));
const businessDate = Timestamp.fromDate(new Date("2026-08-05T12:00:00Z"));

async function fixture() {
  const company = `preflight-${randomUUID()}`, admin = `${company}-admin`, rep = `${company}-rep`;
  const c = `companies/${company}`, bookId = "synthetic-book", b = `${c}/books/${bookId}`;
  const paths = {company: c, book: b, policy: `${b}/policy_revisions/policy-v1`,
    mapping: `${b}/settlement_mappings/mapping-v1`, period: `${b}/periods/period-v1`,
    binding: `${b}/currency_bindings/binding-v1`, companyAccount: `${b}/chart_accounts/company-control`,
    repAccount: `${b}/chart_accounts/rep-control`, lock: `${c}/maintenance_locks/cash_reconciliation`};
  const scoped = (id) => ({id, companyId: company, bookId, revisionId: id, approvalStatus: "approved"});
  const batch = db.batch();
  batch.set(db.doc(c), {id: company, active: true, activeBookId: bookId});
  for (const [uid, role] of [[admin, "admin"], [rep, "sales_rep"]]) {
    batch.set(db.doc(`users/${uid}`), {uid, name: uid, companyId: company, role, active: true, approvalStatus: "approved"});
  }
  batch.set(db.doc(b), {...scoped(bookId), revisionId: "book-v1", active: true, mode: "configuration",
    settlementPreflightEnabled: true, journalPostingEnabled: false, currency: "JOD", moneyScale: 3,
    policyRevisionId: "policy-v1", settlementMappingRevisionId: "mapping-v1", settlementPeriodId: "period-v1"});
  batch.set(db.doc(paths.policy), {...scoped("policy-v1"), currency: "JOD", moneyScale: 3,
    accountingDateBasis: "settlement_business_date", legacyCurrencyBindingId: "binding-v1"});
  batch.set(db.doc(paths.binding), {...scoped("binding-v1"), currency: "JOD", moneyScale: 3,
    sourceCollection: "settlements", postingSource: "recordCashSettlement", settlementMetadataVersion: 1});
  batch.set(db.doc(paths.mapping), {...scoped("mapping-v1"), companyCashAccountId: "company-control",
    companyCashAccountRevisionId: "company-account-v1", representativeCashAccountId: "rep-control",
    representativeCashAccountRevisionId: "rep-account-v1"});
  for (const [path, id, revisionId] of [[paths.companyAccount, "company-control", "company-account-v1"],
    [paths.repAccount, "rep-control", "rep-account-v1"]]) {
    batch.set(db.doc(path), {...scoped(id), revisionId, currency: "JOD", moneyScale: 3,
      accountType: "asset", control: "cash", active: true, postingAllowed: true, requiresTreasuryDimension: true});
  }
  batch.set(db.doc(paths.period), {...scoped("period-v1"), status: "open",
    startsAt: Timestamp.fromDate(new Date("2026-01-01T00:00:00Z")), endsAt: Timestamp.fromDate(new Date("2027-01-01T00:00:00Z"))});
  for (const [id, account, uid, amount] of [[`rep_${rep}`, "rep_cash", rep, 100.111], ["company_cash", "company_cash", "", 20.222]]) {
    batch.set(db.doc(`${c}/cash_balances/${id}`), {id, companyId: company, cashAccount: account, salesRepId: uid, amount});
  }
  await batch.commit();
  const key = "preflight-settlement-key";
  const input = {salesRepId: rep, amount: 30.123, settlementDate: businessDate, notes: "Synthetic preflight settlement"};
  const posted = await recordCashSettlementTransaction(db, admin, company, key, input);
  const settlementId = posted.settlementId;
  Object.assign(paths, {settlement: `${c}/settlements/${settlementId}`, out: `${c}/cash_movements/${settlementId}_rep_out`,
    incoming: `${c}/cash_movements/${settlementId}_company_in`, repBalance: `${c}/cash_balances/rep_${rep}`,
    companyBalance: `${c}/cash_balances/company_cash`, legacy: `${c}/financial_ledger_entries/settlement_${settlementId}_transfer`});
  return {company, admin, rep, c, b, bookId, paths, settlementId, input, key,
    preflight: (overrides = {}, uid = admin, firestore = db) => preflightSettlementTransaction(
      firestore, uid, {companyId: company, settlementId, ...overrides})};
}
async function financialSnapshot(f) {
  const names = ["settlements", "cash_movements", "cash_balances", "financial_ledger_entries"];
  const paths = names.map((name) => `${f.c}/${name}`).concat(
    ["journal_entries", "source_keys", "events", "audit_events", "request_keys", "outbox", "posting_lanes"].map((name) => `${f.b}/${name}`));
  const results = await Promise.all(paths.map((path) => db.collection(path).get()));
  return Object.fromEntries(results.flatMap((s) => s.docs.map((d) => [d.ref.path, {data: d.data(), updateTime: d.updateTime}])));
}
function wrapTransaction(wrap) {
  return {doc: db.doc.bind(db), runTransaction: (callback) => db.runTransaction((t) => wrap(t, callback))};
}
function proxyTransaction(t, intercept) {
  return new Proxy(t, {get(target, name) {
    const override = intercept(name);
    if (override) return override;
    const value = target[name];
    return typeof value === "function" ? value.bind(target) : value;
  }});
}

test("preflight resolves approved scoped records and the actual committed settlement without writes", async () => {
  const f = await fixture(), before = await financialSnapshot(f);
  const result = await f.preflight();
  assert.equal(result.mode, "committed_settlement_read_only");
  assert.equal(result.intent.amountUnits, "30123");
  assert.deepEqual(result.intent.lines.map((l) => [l.account.ledgerAccountKey, l.debitUnits, l.creditUnits]),
    [["company_cash", "30123", "0"], [`rep_cash:${f.rep}`, "0", "30123"]]);
  assert.equal(result.intent.lines[1].account.holderUid, f.rep);
  assert.notEqual(result.intent.lines[1].account.holderUid, f.admin);
  assert.equal(result.sourceKey.state, "absent");
  assert.match(result.preflightDigest, /^[a-f0-9]{64}$/);
  assert.equal(result.context.policyRevisionId, "policy-v1");
  assert.deepEqual(result.positions.map((p) => p.amountUnits), ["69988", "50345"]);
  assert.equal(new Set(result.observations.map((o) => o.path)).size, result.observations.length);
  assert.equal(result.observations.length, 17); // Shared/cached source heads need no further reads.
  assert.equal(result.timestamps.journalCommittedAt, null);
  assert.deepEqual(result.timestamps.accountingDate, {seconds: businessDate.seconds, nanoseconds: businessDate.nanoseconds});
  const source = await db.doc(f.paths.settlement).get();
  assert.deepEqual(result.timestamps.sourceCommittedAt, {seconds: source.createTime.seconds, nanoseconds: source.createTime.nanoseconds});
  assert.deepEqual(result.timestamps.sourceRecordedAt, {seconds: source.data().postedAt.seconds, nanoseconds: source.data().postedAt.nanoseconds});
  const companyObservation = result.observations.find((o) => o.path === f.c);
  assert.deepEqual(result.timestamps.transactionReadTime, companyObservation.readTime);
  assert.ok(result.timestamps.transactionReadTime.seconds >= result.timestamps.sourceCommittedAt.seconds);
  assert.deepEqual(await financialSnapshot(f), before);
  assert.ok(Object.isFrozen(result) && Object.isFrozen(result.intent.lines[0].account));
});

test("preflight duplicates and concurrent identical requests remain deterministic without reserving source keys", async () => {
  const f = await fixture(), before = await financialSnapshot(f);
  const results = await Promise.all(Array.from({length: 4}, () => f.preflight()));
  assert.equal(new Set(results.map((r) => r.intent.id)).size, 1);
  assert.equal(new Set(results.map((r) => r.preflightDigest)).size, 1);
  assert.deepEqual((await f.preflight({expectedPreflightDigest: results[0].preflightDigest})).intent, results[0].intent);
  assert.deepEqual(await financialSnapshot(f), before);
});

test("preflight matches an existing source binding without claiming or creating a journal", async () => {
  const f = await fixture(), first = await f.preflight();
  await db.doc(first.sourceKey.path).set({schemaVersion: 1, companyId: f.company, bookId: f.bookId,
    sourceCollection: "settlements", sourceId: f.settlementId, action: first.intent.action, intentId: first.intent.id,
    payloadDigest: first.intent.payloadDigest, preflightDigest: first.preflightDigest});
  const before = await financialSnapshot(f), replay = await f.preflight();
  assert.equal(replay.sourceKey.state, "matching_binding");
  assert.equal(replay.timestamps.journalCommittedAt, null);
  assert.equal((await db.collection(`${f.b}/journal_entries`).get()).size, 0);
  assert.deepEqual(await financialSnapshot(f), before);
  for (const field of ["companyId", "bookId", "sourceId", "action", "intentId", "payloadDigest", "preflightDigest"]) {
    const original = (await db.doc(first.sourceKey.path).get()).data()[field];
    await db.doc(first.sourceKey.path).update({[field]: "conflict"});
    const conflictBefore = await financialSnapshot(f);
    await assert.rejects(() => f.preflight(), {code: "already-exists"});
    assert.deepEqual(await financialSnapshot(f), conflictBefore);
    await db.doc(first.sourceKey.path).update({[field]: original});
  }
});

test("preflight rejects changed approved context on retry while keeping the existing source intent identity", async () => {
  const f = await fixture(), first = await f.preflight();
  await db.doc(f.paths.book).update({revisionId: "book-v2"});
  const changed = await f.preflight();
  assert.equal(changed.intent.id, first.intent.id);
  assert.notEqual(changed.preflightDigest, first.preflightDigest);
  const before = await financialSnapshot(f);
  await assert.rejects(() => f.preflight({expectedPreflightDigest: first.preflightDigest}), {code: "already-exists"});
  await assert.rejects(() => f.preflight({expectedPreflightDigest: "not-a-digest"}), {code: "failed-precondition"});
  assert.deepEqual(await financialSnapshot(f), before);
});

test("preflight supports an explicit shared chart control with separate actual treasury dimensions", async () => {
  const f = await fixture();
  await db.doc(f.paths.mapping).update({representativeCashAccountId: "company-control", representativeCashAccountRevisionId: "company-account-v1"});
  const result = await f.preflight();
  assert.equal(result.intent.lines[0].account.accountId, result.intent.lines[1].account.accountId);
  assert.notEqual(result.intent.lines[0].account.treasuryAccountId, result.intent.lines[1].account.treasuryAccountId);
  assert.equal(result.observations.length, 16);
});

test("preflight accepts a later validated cash head and preserves the earlier settlement balances", async () => {
  const f = await fixture(), first = await f.preflight();
  await recordCashSettlementTransaction(db, f.admin, f.company, "later-settlement-key", {...f.input, amount: 1});
  const before = await financialSnapshot(f), later = await f.preflight({expectedPreflightDigest: first.preflightDigest});
  assert.deepEqual(later.positions.map((p) => p.amountUnits), ["68988", "51345"]);
  assert.deepEqual(later.intent.movements.map((m) => m.balanceAfterUnits), ["69988", "50345"]);
  assert.equal(later.preflightDigest, first.preflightDigest);
  assert.equal(later.observations.length, 19);
  assert.deepEqual(await financialSnapshot(f), before);
});

test("preflight racing the existing settlement writer sees a consistent cash position and adds no effects", async () => {
  const f = await fixture();
  const [preflight, posted] = await Promise.all([f.preflight(),
    recordCashSettlementTransaction(db, f.admin, f.company, "race-settlement-key", {...f.input, amount: 1})]);
  assert.equal(posted.alreadyPosted, false);
  assert.ok(["69988", "68988"].includes(preflight.positions[0].amountUnits));
  assert.equal((await db.doc(f.paths.repBalance).get()).data().amount, 68.988);
  assert.equal((await db.doc(f.paths.companyBalance).get()).data().amount, 51.345);
  assert.equal((await db.collection(`${f.c}/cash_movements`).get()).size, 4);
  assert.equal((await db.collection(`${f.c}/settlements`).get()).size, 2);
  assert.equal((await db.collection(`${f.b}/journal_entries`).get()).size, 0);
});

test("preflight automatically retries a transaction with fresh local observations and no writes", async () => {
  const f = await fixture(), before = await financialSnapshot(f);
  let attempts = 0;
  const wrapped = wrapTransaction(async (transaction, callback) => {
    const guarded = proxyTransaction(transaction, (name) => ["set", "create", "update", "delete"].includes(name) ?
      () => { throw new Error("Preflight attempted a write"); } : undefined);
    const result = await callback(guarded);
    if (++attempts === 1) throw Object.assign(new Error("Synthetic ABORTED read transaction"), {code: 10});
    return result;
  });
  const result = await f.preflight({}, f.admin, wrapped);
  assert.equal(attempts, 2);
  assert.equal(result.observations.length, 17);
  assert.deepEqual(await financialSnapshot(f), before);
});

test("preflight retries re-read and reject an account deactivated during contention", async () => {
  const f = await fixture(), before = await financialSnapshot(f);
  let attempts = 0, mutation;
  const wrapped = wrapTransaction(async (transaction, callback) => {
    if (mutation) await mutation;
    attempts += 1;
    const result = await callback(transaction);
    if (attempts === 1) {
      mutation = db.doc(f.paths.repAccount).update({active: false});
      throw Object.assign(new Error("Synthetic ABORTED before configuration change"), {code: 10});
    }
    return result;
  });
  await assert.rejects(() => f.preflight({}, f.admin, wrapped), {code: "failed-precondition"});
  assert.equal(attempts, 2);
  await mutation;
  assert.deepEqual(await financialSnapshot(f), before);
});

test("preflight propagates transaction failure and a later retry succeeds without partial financial changes", async () => {
  const f = await fixture(), before = await financialSnapshot(f);
  const wrapped = wrapTransaction((transaction, callback) => {
    let reads = 0;
    return callback(proxyTransaction(transaction, (name) => name === "getAll" ? (...refs) => {
      if (++reads === 3) throw Object.assign(new Error("Synthetic transaction transport failure"), {code: 9});
      return transaction.getAll(...refs);
    } : undefined));
  });
  await assert.rejects(() => f.preflight({}, f.admin, wrapped), {code: 9});
  assert.deepEqual(await financialSnapshot(f), before);
  assert.equal((await f.preflight()).sourceKey.state, "absent");
});

test("preflight obeys read-before-write ordering in a caller-owned Firestore transaction", async () => {
  const f = await fixture(), before = await financialSnapshot(f);
  const marker = db.doc(`${f.b}/preflight_test/rollback-marker`);
  await assert.rejects(() => db.runTransaction(async (t) => {
    t.set(marker, {synthetic: true});
    await prepareSettlementPreflight(t, db, f.admin, {companyId: f.company, settlementId: f.settlementId});
  }), /reads.*before.*writes/i);
  assert.equal((await marker.get()).exists, false);
  assert.deepEqual(await financialSnapshot(f), before);
});

test("preflight reuses current authorization and rejects unauthorized and cross-company access", async () => {
  const f = await fixture(), foreign = await fixture(), before = await financialSnapshot(f);
  for (const [uid, code] of [[undefined, "unauthenticated"], [f.rep, "permission-denied"],
    [foreign.admin, "permission-denied"], ["missing-user", "permission-denied"]]) {
    await assert.rejects(() => preflightSettlementTransaction(db, uid,
      {companyId: f.company, settlementId: f.settlementId}), {code});
  }
  await db.doc(`users/${f.admin}`).update({active: false});
  await assert.rejects(() => f.preflight(), {code: "permission-denied"});
  assert.deepEqual(await financialSnapshot(f), before);
});

const failures = [
  ["missing company", "company", null], ["inactive company", "company", {active: false}],
  ["missing active book", "company", {activeBookId: FieldValue.delete()}],
  ["missing book", "book", null], ["foreign book", "book", {companyId: "foreign"}],
  ["unapproved book", "book", {approvalStatus: "pending"}], ["posting enabled", "book", {journalPostingEnabled: true}],
  ["preflight disabled", "book", {settlementPreflightEnabled: false}], ["live book mode", "book", {mode: "live"}],
  ["missing policy", "policy", null], ["unapproved policy", "policy", {approvalStatus: "pending"}],
  ["foreign policy book", "policy", {bookId: "foreign"}], ["policy revision mismatch", "policy", {revisionId: "other"}],
  ["policy currency conflict", "policy", {currency: "USD"}], ["policy scale conflict", "policy", {moneyScale: 2}],
  ["unsupported date policy", "policy", {accountingDateBasis: "server_now"}],
  ["missing currency binding", "binding", null], ["unapproved currency binding", "binding", {approvalStatus: "pending"}],
  ["binding currency conflict", "binding", {currency: "USD"}], ["binding source conflict", "binding", {sourceCollection: "receipts"}],
  ["unverified source currency", "policy", {legacyCurrencyBindingId: FieldValue.delete()}],
  ["missing mapping", "mapping", null], ["unapproved mapping", "mapping", {approvalStatus: "pending"}],
  ["missing account identity", "mapping", {companyCashAccountId: FieldValue.delete()}],
  ["path injection", "mapping", {companyCashAccountId: "other/account"}],
  ["pinned account mismatch", "mapping", {representativeCashAccountRevisionId: "other-revision"}],
  ["missing chart account", "repAccount", null], ["foreign chart account", "repAccount", {companyId: "foreign"}],
  ["inactive chart account", "repAccount", {active: false}], ["unapproved chart account", "companyAccount", {approvalStatus: "pending"}],
  ["nonposting group", "companyAccount", {postingAllowed: false}], ["revenue account", "companyAccount", {accountType: "income"}],
  ["missing control dimensions", "repAccount", {requiresTreasuryDimension: false}],
  ["chart currency conflict", "companyAccount", {currency: "USD"}],
  ["missing period", "period", null], ["closed period", "period", {status: "closed"}],
  ["foreign period", "period", {companyId: "foreign"}],
  ["out of period", "period", {startsAt: Timestamp.fromDate(new Date("2026-09-01T00:00:00Z"))}],
  ["invalid period boundary", "period", {endsAt: Timestamp.fromDate(new Date("2025-01-01T00:00:00Z"))}],
  ["reconciliation lock", "lock", {active: true}], ["malformed reconciliation lock", "lock", {}],
  ["missing settlement", "settlement", null], ["foreign source", "settlement", {companyId: "foreign"}],
  ["unposted source", "settlement", {status: "draft"}, "invalid-argument"],
  ["malformed amount", "settlement", {amount: "NaN"}, "invalid-argument"],
  ["excess precision", "settlement", {amount: 30.1234}, "invalid-argument"],
  ["missing OUT", "out", null], ["missing IN", "incoming", null],
  ["foreign movement", "out", {companyId: "foreign"}, "invalid-argument"],
  ["inconsistent movement amount", "incoming", {amount: 30.124}, "invalid-argument"],
  ["inconsistent reciprocal reference", "out", {counterpartMovementId: "other"}, "invalid-argument"],
  ["wrong actual holder", "out", {holderUid: "other"}, "invalid-argument"],
  ["cross-currency movement", "incoming", {currency: "USD"}, "invalid-argument"],
  ["missing legacy projection", "legacy", null], ["wrong legacy direction", "legacy", {debitAccountKey: "sales"}],
  ["wrong legacy amount", "legacy", {amount: 30.124}],
  ["legacy currency conflict", "legacy", {currency: "USD"}],
  ["missing cash position", "repBalance", null], ["foreign cash position", "companyBalance", {companyId: "foreign"}],
  ["wrong cash holder", "repBalance", {holderUid: "other"}],
  ["stale cash amount", "repBalance", {amount: 69.989}], ["wrong position currency", "companyBalance", {currency: "USD"}],
  ["malformed cash amount", "repBalance", {amount: "NaN"}, "invalid-argument"],
  ["excess cash precision", "repBalance", {amount: 69.9881}, "invalid-argument"],
  ["missing head pointer", "repBalance", {lastMovementId: FieldValue.delete()}],
  ["unknown head pointer", "repBalance", {lastMovementId: "missing-head"}],
  ["stale balance timestamp", "companyBalance", {updatedAt: new Timestamp(0, 0)}],
];
for (const [name, path, change, code = "failed-precondition"] of failures) {
  test(`preflight blocks ${name} without changing financial records`, async () => {
    const f = await fixture(), ref = db.doc(f.paths[path]);
    if (change === null) await ref.delete();
    else await ref.set(change, {merge: true});
    const before = await financialSnapshot(f);
    await assert.rejects(() => f.preflight(), {code});
    assert.deepEqual(await financialSnapshot(f), before);
  });
}

test("preflight verifies representative membership independently of creator and seller", async () => {
  const f = await fixture();
  for (const change of [{companyId: "foreign"}, {role: "admin"}, {active: false}, {approvalStatus: "pending"}]) {
    const ref = db.doc(`users/${f.rep}`), original = (await ref.get()).data();
    await ref.set({...original, ...change});
    const before = await financialSnapshot(f);
    await assert.rejects(() => f.preflight(), {code: "failed-precondition"});
    assert.deepEqual(await financialSnapshot(f), before);
    await ref.set(original);
  }
});

test("preflight rejects forged stored timestamps instead of treating them as commit metadata", async () => {
  const f = await fixture(), forged = new Timestamp(0, 123);
  const batch = db.batch();
  for (const path of [f.paths.settlement, f.paths.out, f.paths.incoming]) {
    batch.update(db.doc(path), {createdAt: forged, postedAt: forged, ...(path === f.paths.settlement ? {updatedAt: forged} : {})});
  }
  const beforeCommit = await db.doc(f.paths.settlement).get();
  await batch.commit();
  const before = await financialSnapshot(f);
  await assert.rejects(() => f.preflight(), {code: "failed-precondition"});
  assert.deepEqual(await financialSnapshot(f), before);
  assert.ok((await db.doc(f.paths.settlement).get()).createTime.isEqual(beforeCommit.createTime));
});

test("preflight rejects separately recreated movement evidence even when its stored metadata matches", async () => {
  const f = await fixture(), ref = db.doc(f.paths.out), original = (await ref.get()).data();
  await ref.delete();
  await ref.set(original);
  const before = await financialSnapshot(f);
  await assert.rejects(() => f.preflight(), {code: "failed-precondition"});
  assert.deepEqual(await financialSnapshot(f), before);
});

test("preflight uses explicitly stored currency without requiring or inventing a legacy binding", async () => {
  const f = await fixture(), batch = db.batch();
  for (const path of [f.paths.settlement, f.paths.out, f.paths.incoming]) batch.update(db.doc(path), {currency: "JOD", moneyScale: 3});
  batch.update(db.doc(f.paths.policy), {legacyCurrencyBindingId: FieldValue.delete()});
  await batch.commit();
  const before = await financialSnapshot(f), result = await f.preflight();
  assert.equal(result.context.legacyCurrencyBindingRevisionId, null);
  assert.equal(result.observations.length, 16);
  assert.deepEqual(await financialSnapshot(f), before);
});

test("preflight re-reads and validates an advanced current cash head without fabricating earlier balances", async () => {
  const f = await fixture();
  await recordCashSettlementTransaction(db, f.admin, f.company, "head-validation-settlement", {...f.input, amount: 1});
  const head = db.doc(`${f.c}/cash_movements/settlement_head-validation-settlement_rep_out`);
  for (const change of [{companyId: "foreign"}, {holderUid: f.admin}, {currency: "USD"},
    {balanceAfter: 68.989}, {direction: "unknown"}, {createdAt: new Timestamp(0, 0)}]) {
    const original = (await head.get()).data();
    await head.update(change);
    const before = await financialSnapshot(f);
    await assert.rejects(() => f.preflight(), {code: "failed-precondition"});
    assert.deepEqual(await financialSnapshot(f), before);
    await head.set(original);
  }
});

test("preflight keeps existing callable and writer behavior unchanged, including ordinary settlement replay", async () => {
  const f = await fixture(), before = await financialSnapshot(f);
  await f.preflight();
  assert.deepEqual(await recordCashSettlementTransaction(db, f.admin, f.company, f.key, f.input),
    {settlementId: f.settlementId, alreadyPosted: true});
  assert.deepEqual(await financialSnapshot(f), before);
  // Missing all accounting configuration still cannot block the existing writer.
  await db.doc(f.paths.book).delete();
  const result = await recordCashSettlementTransaction(db, f.admin, f.company, "ordinary-next-settlement", {...f.input, amount: 1});
  assert.equal(result.alreadyPosted, false);
  for (const file of ["record_cash_settlement.ts", "../index.ts"]) {
    assert.doesNotMatch(readFileSync(join(__dirname, "../src/trusted", file), "utf8"), /prepareSettlementPreflight|preflightSettlementTransaction/);
  }
});
