"use strict";
const assert = require("node:assert/strict");
const {test, after} = require("node:test");
const {randomUUID} = require("node:crypto");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) {
  throw new Error("Pending settlement tests require a dedicated loopback Firestore emulator.");
}
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {recordCashSettlementTransaction: post} = require("../lib/trusted/record_cash_settlement");
const {preflightSettlementTransaction} = require("../lib/trusted/settlement_preflight");
const {pendingSettlementEvidenceTransaction: prepare, preparePendingSettlementEvidence: inTransaction} = require("../lib/trusted/settlement_pending_evidence");
const {buildSettlementJournalEconomics} = require("../lib/trusted/settlement_journal_intent");
const app = initializeApp({projectId: "demo-fatoora-phase2b6"}, "pending-settlement-tests");
const db = getFirestore(app);
after(() => deleteApp(app));
const date = Timestamp.fromDate(new Date("2026-08-05T12:00:00Z"));
const plainTime = t => ({seconds: t.seconds, nanoseconds: t.nanoseconds});
const clone = x => JSON.parse(JSON.stringify(x));
const code = expected => error => {assert.equal(error.code, expected, error.stack); return true;};

async function fixture() {
  const company = `pending-${randomUUID()}`, admin = `${company}-admin`, rep = `${company}-rep`;
  const c = `companies/${company}`, bookId = "synthetic-book", b = `${c}/books/${bookId}`;
  const paths = {company: c, book: b, policy: `${b}/policy_revisions/policy-v1`, mapping: `${b}/settlement_mappings/mapping-v1`,
    period: `${b}/periods/period-v1`, binding: `${b}/currency_bindings/binding-v1`, companyAccount: `${b}/chart_accounts/company-control`,
    repAccount: `${b}/chart_accounts/rep-control`, lock: `${c}/maintenance_locks/cash_reconciliation`,
    repBalance: `${c}/cash_balances/rep_${rep}`, companyBalance: `${c}/cash_balances/company_cash`};
  const scoped = id => ({id, companyId: company, bookId, revisionId: id, approvalStatus: "approved"});
  const batch = db.batch();
  batch.set(db.doc(c), {id: company, active: true, activeBookId: bookId});
  for (const [uid, role] of [[admin, "admin"], [rep, "sales_rep"]]) {
    batch.set(db.doc(`users/${uid}`), {uid, name: uid, role, companyId: company, active: true, approvalStatus: "approved"});
  }
  batch.set(db.doc(b), {...scoped(bookId), revisionId: "book-v1", active: true, mode: "configuration",
    settlementPreflightEnabled: true, journalPostingEnabled: false, currency: "JOD", moneyScale: 3,
    policyRevisionId: "policy-v1", settlementMappingRevisionId: "mapping-v1", settlementPeriodId: "period-v1"});
  batch.set(db.doc(paths.policy), {...scoped("policy-v1"), currency: "JOD", moneyScale: 3,
    accountingDateBasis: "settlement_business_date", legacyCurrencyBindingId: "binding-v1"});
  batch.set(db.doc(paths.binding), {...scoped("binding-v1"), currency: "JOD", moneyScale: 3,
    sourceCollection: "settlements", postingSource: "recordCashSettlement", settlementMetadataVersion: 1});
  batch.set(db.doc(paths.mapping), {...scoped("mapping-v1"), companyCashAccountId: "company-control",
    companyCashAccountRevisionId: "company-account-v1", representativeCashAccountId: "rep-control", representativeCashAccountRevisionId: "rep-account-v1"});
  for (const [path, id, revisionId] of [[paths.companyAccount, "company-control", "company-account-v1"],
    [paths.repAccount, "rep-control", "rep-account-v1"]]) batch.set(db.doc(path), {...scoped(id), revisionId, currency: "JOD", moneyScale: 3,
    accountType: "asset", control: "cash", active: true, postingAllowed: true, requiresTreasuryDimension: true});
  batch.set(db.doc(paths.period), {...scoped("period-v1"), status: "open",
    startsAt: Timestamp.fromDate(new Date("2026-01-01T00:00:00Z")), endsAt: Timestamp.fromDate(new Date("2027-01-01T00:00:00Z"))});
  for (const [id, account, uid, amount] of [[`rep_${rep}`, "rep_cash", rep, 100.111], ["company_cash", "company_cash", "", 20.222]]) {
    batch.set(db.doc(`${c}/cash_balances/${id}`), {id, companyId: company, cashAccount: account, salesRepId: uid, amount});
  }
  await batch.commit();
  await post(db, admin, company, "existing-cash-head-key", {salesRepId: rep, amount: 30.123, settlementDate: date});
  Object.assign(paths, {repHead: `${c}/cash_movements/settlement_existing-cash-head-key_rep_out`,
    companyHead: `${c}/cash_movements/settlement_existing-cash-head-key_company_in`});
  const input = {companyId: company, idempotencyKey: "pending-settlement-key", salesRepId: rep,
    amount: "1.234", settlementDate: plainTime(date), notes: "Synthetic pending settlement"};
  return {company, admin, rep, c, b, bookId, paths, input,
    prepare: (overrides = {}, expected, uid = admin, database = db) => prepare(database, uid, {...input, ...overrides}, expected),
    advance: () => post(db, admin, company, `advanced-${randomUUID()}`, {salesRepId: rep, amount: 1, settlementDate: date})};
}
async function financialSnapshot(f) {
  const result = [];
  for (const collection of ["settlements", "cash_movements", "cash_balances", "financial_ledger_entries",
    "books/synthetic-book/journal_entries", "books/synthetic-book/events", "books/synthetic-book/source_keys",
    "books/synthetic-book/outbox", "books/synthetic-book/request_keys", "books/synthetic-book/audit_events", "books/synthetic-book/posting_lanes"]) {
    const snapshots = await db.collection(`${f.c}/${collection}`).get();
    result.push(...snapshots.docs.map(s => ({path: s.ref.path, version: plainTime(s.updateTime), data: s.data()})));
  }
  return result.sort((a, b) => a.path.localeCompare(b.path));
}
function proxy(t, overrides) {return new Proxy(t, {get(target, name) {const v = overrides[name] || target[name];return typeof v === "function" ? v.bind(target) : v;}});}
function wrapped(callback) {return {doc: db.doc.bind(db), runTransaction: cb => db.runTransaction(t => callback(t, cb))};}
async function noJournal(f) {
  for (const collection of ["journal_entries", "events", "source_keys", "outbox", "request_keys", "audit_events", "posting_lanes"]) {
    assert.equal((await db.collection(`${f.b}/${collection}`).get()).size, 0);
  }
}

test("pending evidence binds exact economics, custody, approved revisions and actual snapshot versions without writes", async () => {
  const f = await fixture(), before = await financialSnapshot(f), result = await f.prepare(), e = result.evidence;
  assert.equal(e.mode, "pending_settlement"); assert.equal(e.source.status, "pending");
  assert.equal(e.source.actor.uid, f.admin); assert.equal(e.source.salesRepId, f.rep);
  assert.equal(e.source.sellerIdentityStatus, "not_applicable"); assert.equal(e.source.collectorIdentityStatus, "not_applicable");
  assert.equal(e.economics.currency, "JOD"); assert.equal(e.economics.moneyScale, 3);
  assert.deepEqual(e.economics.lines.map(l => [l.account.holderUid, l.debitUnits, l.creditUnits]), [[f.company, "1234", "0"], [f.rep, "0", "1234"]]);
  assert.deepEqual(e.cashEffects.map(p => [p.balanceBeforeUnits, p.balanceAfterUnits]), [["69988", "68754"], ["50345", "51579"]]);
  assert.equal(e.cashEffects[0].counterpartMovementId, e.cashEffects[1].id);
  assert.equal(e.context.policyRevisionId, "policy-v1"); assert.equal(e.context.mappingRevisionId, "mapping-v1");
  assert.equal(e.context.legacyCurrencyBindingRevisionId, "binding-v1");
  for (const k of ["requestDigest", "economicDigest", "configurationDigest", "preflightDigest"]) assert.match(e[k], /^[a-f0-9]{64}$/);
  assert.equal(result.observation.documents.length, 22); // Plus one existing resolver read: 23 document reads.
  assert.equal(new Set(e.versions.map(v => v.path)).size, e.versions.length);
  assert.ok(Object.isFrozen(e) && Object.isFrozen(e.economics.lines[0].account) && Object.isFrozen(e.versions[0]));
  assert.throws(() => {e.cashEffects[0].balanceAfterUnits = "0";}, TypeError);
  assert.deepEqual(await financialSnapshot(f), before); await noJournal(f);
});

test("pending timestamps retain nanos and SDK witnesses while all unknown source/journal commit clocks remain null", async () => {
  const f = await fixture(), nanos = {seconds: date.seconds, nanoseconds: 123456789};
  const {evidence: e, observation} = await f.prepare({settlementDate: nanos});
  assert.deepEqual(e.timestamps, {accountingDate: nanos, sourceRecordedAt: null, sourceCommittedAt: null, journalRecordedAt: null, journalCommittedAt: null});
  assert.equal(e.timestampContract.recordedEqualsCommit, false);
  assert.deepEqual(observation.transactionReadTime, observation.documents.find(d => d.path === f.c).readTime);
  for (const p of e.positions) {
    const balance = await db.doc(p.path).get(), head = await db.doc(`${f.c}/cash_movements/${p.lastMovementId}`).get();
    assert.deepEqual(p.balanceCommittedAt, plainTime(balance.updateTime));
    assert.deepEqual(p.headCommittedAt, plainTime(head.createTime));
    assert.deepEqual(p.headRecordedAt, plainTime(head.data().createdAt));
    assert.deepEqual(p.updatedAt, plainTime(balance.data().updatedAt));
    assert.deepEqual(p.balanceCommittedAt, p.headCommittedAt);
  }
  const futureBusinessDate = Timestamp.fromDate(new Date("2026-12-20T00:00:00Z"));
  assert.deepEqual((await f.prepare({settlementDate: futureBusinessDate})).evidence.timestamps.accountingDate, plainTime(futureBusinessDate));
});

test("identical retries and parallel preparation preserve evidence and identities without acquiring a durable reservation", async () => {
  const f = await fixture(), first = await f.prepare(), before = await financialSnapshot(f);
  const results = await Promise.all(Array.from({length: 4}, () => f.prepare({}, clone(first.evidence))));
  for (const r of results) assert.deepEqual(r.evidence, first.evidence);
  assert.ok(results.some(r => JSON.stringify(r.observation) !== JSON.stringify(first.observation)));
  assert.deepEqual((await f.prepare({amount: 1.234, notes: `  ${f.input.notes}  `})).evidence, first.evidence);
  const conflicting = await f.prepare({amount: "2.345"});
  assert.equal(conflicting.evidence.id, first.evidence.id);
  assert.notEqual(conflicting.evidence.requestDigest, first.evidence.requestDigest);
  await assert.rejects(() => f.prepare({}, conflicting.evidence), code("already-exists"));
  assert.deepEqual(await financialSnapshot(f), before); await noJournal(f);
});

for (const [name, change] of [["amount", {amount: "2.345"}], ["business date", {settlementDate: {seconds: date.seconds + 1, nanoseconds: 0}}],
  ["nanoseconds", {settlementDate: {seconds: date.seconds, nanoseconds: 1}}], ["notes", {notes: "different"}], ["source identity", {idempotencyKey: "different-source-key"}]]) {
  test(`same expected evidence rejects conflicting ${name}`, async () => {
    const f = await fixture(), first = await f.prepare(), before = await financialSnapshot(f);
    await assert.rejects(() => f.prepare(change, first.evidence), code("already-exists"));
    assert.deepEqual(await financialSnapshot(f), before);
  });
}
test("conflicting authenticated admin, holder and company cannot reuse pending evidence", async () => {
  const f = await fixture(), e = (await f.prepare()).evidence;
  const otherAdmin = `${f.company}-other-admin`;
  await db.doc(`users/${otherAdmin}`).set({uid: otherAdmin, companyId: f.company, role: "admin", name: "other", active: true, approvalStatus: "approved"});
  await assert.rejects(() => f.prepare({}, e, otherAdmin), code("already-exists"));
  const other = await fixture();
  await assert.rejects(() => other.prepare({}, e), code("already-exists"));
  await assert.rejects(() => f.prepare({salesRepId: other.rep}, e), code("failed-precondition"));
  assert.notEqual((await other.prepare()).evidence.id, e.id);
  assert.notEqual((await f.prepare({idempotencyKey: "different-source-key"})).evidence.id, e.id);
});

test("another valid company representative cannot reuse the source identity with reviewed evidence", async () => {
  const f = await fixture(), e = (await f.prepare()).evidence, rep = `${f.company}-another-rep`;
  await db.doc(`users/${rep}`).create({uid: rep, name: rep, companyId: f.company, role: "sales_rep", active: true, approvalStatus: "approved"});
  await db.doc(`${f.c}/cash_balances/rep_${rep}`).create({id: `rep_${rep}`, companyId: f.company, cashAccount: "rep_cash", salesRepId: rep, amount: 10});
  await post(db, f.admin, f.company, "other-holder-seed-key", {salesRepId: rep, amount: 1, settlementDate: date});
  const before = await financialSnapshot(f), other = (await f.prepare({salesRepId: rep})).evidence;
  assert.equal(other.id, e.id);assert.notEqual(other.requestDigest, e.requestDigest);
  await assert.rejects(() => f.prepare({salesRepId: rep}, e), code("already-exists"));
  assert.deepEqual(await financialSnapshot(f), before);
});

for (const [name, mutate] of [
  ["amount", e => {e.economics.amountUnits = "1";}], ["debit", e => {e.economics.lines[0].debitUnits = "1";}],
  ["credit", e => {e.economics.lines[1].creditUnits = "1";}], ["holder", e => {e.economics.lines[1].account.holderUid = e.source.actor.uid;}],
  ["account revision", e => {e.economics.lines[0].account.accountRevisionId = "forged";}], ["currency", e => {e.economics.currency = "USD";}],
  ["cash ownership", e => {e.cashEffects[0].holderUid = e.source.actor.uid;}], ["before balance", e => {e.cashEffects[0].balanceBeforeUnits = "0";}],
  ["after balance", e => {e.cashEffects[0].balanceAfterUnits = "0";}], ["target path", e => {e.targets.sourceKey = "companies/foreign/source_keys/key";}],
  ["SDK version", e => {e.versions[0].updateTime = null;}], ["configuration", e => {e.context.bookRevisionId = "forged";}],
  ["posted status", e => {e.source.status = "posted";}], ["seller", e => {e.source.sellerId = e.source.salesRepId;}],
  ["committed timestamp", e => {e.timestamps.sourceCommittedAt = e.timestamps.accountingDate;}],
  ["journal timestamp", e => {e.timestamps.journalCommittedAt = e.timestamps.accountingDate;}],
  ["fabricated equality", e => {e.timestampContract.recordedEqualsCommit = true;}], ["extra field", e => {e.approved = true;}],
  ["economic digest", e => {e.economicDigest = "0".repeat(64);}]
]) test(`pending evidence rejects tampered ${name} even when preflight digest is copied`, async () => {
  const f = await fixture(), e = clone((await f.prepare()).evidence), before = await financialSnapshot(f);mutate(e);
  await assert.rejects(() => f.prepare({}, e), code("invalid-argument"));
  assert.deepEqual(await financialSnapshot(f), before);
});

for (const [name, make] of [
  ["wrong schema", e => ({...e, schemaVersion: 2})], ["wrong mode", e => ({...e, mode: "committed"})],
  ["null", () => null], ["class instance", () => new Date()], ["server transform", () => FieldValue.serverTimestamp()],
  ["cycle", e => {e.cycle = e;return e;}], ["nonfinite", e => ({...e, extra: NaN})], ["oversized string", e => ({...e, extra: "x".repeat(2049)})],
  ["oversized array", e => ({...e, extra: Array(65).fill(0)})], ["sparse array", e => ({...e, extra: Array(3)})],
  ["sparse array with disguised key count", e => {e.extra = [0, 1];delete e.extra[1];e.extra.other = 1;return e;}],
  ["oversized object", e => ({...e, extra: Object.fromEntries(Array.from({length: 65}, (_, i) => [`k${i}`, i]))})],
  ["excess encoded bytes", e => ({...e, extra: Array(64).fill("x".repeat(2048))})],
  ["excess depth", e => {let value = 0;for (let i = 0; i < 17; i++) value = {value};return {...e, extra: value};}],
  ["excess node count", e => ({...e, extra: Array.from({length: 64}, () => Array(64).fill(0))})],
  ["symbol", e => {e[Symbol("hidden")] = "x";return e;}],
  ["nonenumerable", e => {Object.defineProperty(e, "hidden", {value: 1});return e;}],
  ["object accessor", e => {Object.defineProperty(e, "extra", {enumerable: true, get() {throw new Error("must not evaluate accessor");}});return e;}],
  ["array accessor", e => {e.extra = [0];Object.defineProperty(e.extra, "0", {get() {throw new Error("must not evaluate accessor");}});return e;}]
]) test(`pending evidence rejects ${name} within bounded validation`, async () => {
  const f = await fixture(), e = clone((await f.prepare()).evidence);
  await assert.rejects(() => f.prepare({}, make(e)), code("invalid-argument"));
});

test("a valid cash advance makes reviewed evidence stale, preserves economics and uses fresh head versions", async () => {
  const f = await fixture(), first = (await f.prepare()).evidence;
  await f.advance(); const before = await financialSnapshot(f);
  await assert.rejects(() => f.prepare({}, first), code("failed-precondition"));
  const next = (await f.prepare()).evidence;
  assert.equal(next.id, first.id);assert.equal(next.requestDigest, first.requestDigest);assert.equal(next.economicDigest, first.economicDigest);
  assert.equal(next.configurationDigest, first.configurationDigest);assert.notEqual(next.preflightDigest, first.preflightDigest);
  assert.deepEqual(next.positions.map(p => p.amountUnits), ["68988", "51345"]);
  assert.deepEqual(await financialSnapshot(f), before);
});

for (const target of ["book", "policy", "mapping", "binding", "period", "companyAccount", "repAccount"]) {
  test(`SDK version change to approved ${target} rejects stale evidence even with unchanged revision IDs`, async () => {
    const f = await fixture(), first = (await f.prepare()).evidence, ref = db.doc(f.paths[target]);
    await ref.update({reviewNote: "synthetic configuration touch"});
    const next = (await f.prepare()).evidence;
    assert.equal(next.economicDigest, first.economicDigest);assert.notEqual(next.configurationDigest, first.configurationDigest);
    await assert.rejects(() => f.prepare({}, first), code("failed-precondition"));
  });
}
test("configuration ABA, profile revisions and changed accounting mappings require renewed review", async () => {
  const f = await fixture(), first = (await f.prepare()).evidence, ref = db.doc(f.paths.book);
  await ref.update({active: false});await ref.update({active: true});
  await assert.rejects(() => f.prepare({}, first), code("failed-precondition"));
  const second = (await f.prepare()).evidence;
  await db.doc(`users/${f.admin}`).update({name: "Updated approved admin"});
  await assert.rejects(() => f.prepare({}, second), code("failed-precondition"));
  const third = (await f.prepare()).evidence;
  const batch = db.batch();batch.update(db.doc(f.paths.repAccount), {revisionId: "rep-account-v2"});
  batch.update(db.doc(f.paths.mapping), {representativeCashAccountRevisionId: "rep-account-v2"});await batch.commit();
  await assert.rejects(() => f.prepare({}, third), code("failed-precondition"));
  assert.notEqual((await f.prepare()).evidence.economicDigest, third.economicDigest);
});

for (const target of ["settlement", "repMovement", "companyMovement", "legacyLedger", "sourceKey", "journal", "event"]) {
  test(`an existing ${target} prevents a pending claim, even with a matching-looking binding`, async () => {
    const f = await fixture(), e = (await f.prepare()).evidence;
    // Synthetic collision fixture only; this is not journal posting.
    await db.doc(e.targets[target]).create({syntheticCollision: true, intentId: e.id, preflightDigest: e.preflightDigest});
    const before = await financialSnapshot(f);
    await assert.rejects(() => f.prepare({}, e), code("already-exists"));
    assert.deepEqual(await financialSnapshot(f), before);
  });
}

for (const [name, override] of [
  ["zero", {amount: "0"}], ["negative", {amount: "-1"}], ["precision", {amount: "1.2345"}], ["exponent", {amount: "1e3"}],
  ["trailing precision", {amount: "1.2340"}], ["float residue", {amount: 0.1 + 0.2}], ["infinity", {amount: Infinity}],
  ["unsafe legacy units", {amount: "9007199254740.992"}], ["insufficient cash", {amount: "69.989"}],
  ["slash company", {companyId: "a/b"}], ["slash representative", {salesRepId: "a/b"}], ["invalid key", {idempotencyKey: "../invalid-key"}],
  ["caller-supplied mapping", {mappings: []}], ["caller-supplied timestamp", {committedAt: plainTime(date)}],
  ["long notes", {notes: "x".repeat(2049)}], ["nontext notes", {notes: 5}], ["wrong book", {expectedBookId: "other-book"}],
  ["date string", {settlementDate: "2026-08-05"}], ["Date instance", {settlementDate: new Date()}],
  ["date sentinel", {settlementDate: FieldValue.serverTimestamp()}], ["date unresolved", {settlementDate: null}],
  ["unsafe seconds", {settlementDate: {seconds: Number.MAX_SAFE_INTEGER + 1, nanoseconds: 0}}],
  ["nanosecond overflow", {settlementDate: {seconds: date.seconds, nanoseconds: 1e9}}],
  ["fractional seconds", {settlementDate: {seconds: date.seconds + 0.5, nanoseconds: 0}}],
  ["negative nanoseconds", {settlementDate: {seconds: date.seconds, nanoseconds: -1}}],
]) test(`pending request blocks ${name} without posting`, async () => {
  const f = await fixture(), before = await financialSnapshot(f);
  await assert.rejects(() => f.prepare(override), code(["insufficient cash", "wrong book"].includes(name) ? "failed-precondition" : "invalid-argument"));
  assert.deepEqual(await financialSnapshot(f), before);
});

test("accounting period is lower inclusive and upper exclusive at nanosecond precision", async () => {
  const f = await fixture(), p = (await db.doc(f.paths.period).get()).data();
  assert.deepEqual((await f.prepare({settlementDate: p.startsAt})).evidence.timestamps.accountingDate, plainTime(p.startsAt));
  await f.prepare({settlementDate: new Timestamp(p.endsAt.seconds - 1, 999999999)});
  await assert.rejects(() => f.prepare({settlementDate: p.endsAt}), code("failed-precondition"));
  await assert.rejects(() => f.prepare({settlementDate: new Timestamp(p.startsAt.seconds - 1, 999999999)}), code("failed-precondition"));
});

const configFailures = [
  ["inactive company", "company", {active: false}], ["foreign company", "company", {companyId: "foreign"}],
  ["missing book", "book", null], ["posting enabled", "book", {journalPostingEnabled: true}],
  ["preflight disabled", "book", {settlementPreflightEnabled: false}], ["live book mode", "book", {mode: "live"}],
  ["unapproved policy", "policy", {approvalStatus: "pending"}], ["foreign policy", "policy", {companyId: "foreign"}],
  ["wrong book policy", "policy", {bookId: "foreign"}], ["policy revision mismatch", "policy", {revisionId: "policy-v2"}],
  ["currency mismatch", "policy", {currency: "USD"}], ["precision mismatch", "policy", {moneyScale: 2}],
  ["date basis", "policy", {accountingDateBasis: "commit_date"}], ["missing binding", "binding", null],
  ["binding currency", "binding", {currency: "USD"}], ["binding source", "binding", {postingSource: "untrusted"}],
  ["closed period", "period", {status: "closed"}], ["active lock", "lock", {active: true}], ["ambiguous lock", "lock", {}],
  ["inactive account", "repAccount", {active: false}], ["nonposting account", "companyAccount", {postingAllowed: false}],
  ["nondimensional account", "companyAccount", {requiresTreasuryDimension: false}], ["wrong account type", "repAccount", {accountType: "income"}],
  ["unpinned account", "repAccount", {revisionId: "new-revision"}], ["path injection", "mapping", {companyCashAccountId: "other/account"}],
  ["forged holder", "repBalance", {holderUid: "other"}], ["stale balance", "repBalance", {amount: 69.989}],
  ["foreign head", "repHead", {companyId: "foreign"}], ["wrong cash head", "companyHead", {cashAccount: "rep_cash"}],
  ["forged timestamp", "repHead", {createdAt: new Timestamp(0, 0)}], ["replaced head", "repBalance", {lastMovementId: "missing-head"}],
];
for (const [name, target, change] of configFailures) test(`pending preflight blocks ${name} without changing financial records`, async () => {
  const f = await fixture(), ref = db.doc(f.paths[target]);
  if (change === null) await ref.delete();else await ref.set(change, {merge: true});
  const before = await financialSnapshot(f);
  await assert.rejects(() => f.prepare(), code("failed-precondition"));
  assert.deepEqual(await financialSnapshot(f), before);
});

test("legacy cash requires explicit approved currency binding; dimensional shared control is supported", async () => {
  const f = await fixture();
  await db.doc(f.paths.policy).update({legacyCurrencyBindingId: FieldValue.delete()});
  await assert.rejects(() => f.prepare(), code("failed-precondition"));
  await db.doc(f.paths.policy).update({legacyCurrencyBindingId: "binding-v1"});
  await db.doc(f.paths.mapping).update({representativeCashAccountId: "company-control", representativeCashAccountRevisionId: "company-account-v1"});
  const e = (await f.prepare()).evidence;
  assert.equal(e.economics.lines[0].account.accountId, e.economics.lines[1].account.accountId);
  assert.notEqual(e.economics.lines[0].account.treasuryAccountId, e.economics.lines[1].account.treasuryAccountId);
  assert.equal(e.versions.length, 21);
});

test("absent binding is permitted only when both current balances and heads explicitly declare the currency", async () => {
  const f = await fixture(), batch = db.batch();
  // Replace fixture heads atomically to obtain genuine new createTime witnesses.
  for (const [index, target] of ["repBalance", "companyBalance"].entries()) {
    const balanceRef = db.doc(f.paths[target]), balance = (await balanceRef.get()).data();
    const oldHead = (await db.doc(f.paths[index === 0 ? "repHead" : "companyHead"]).get()).data();
    const id = `explicit-currency-${index}`;
    batch.create(db.doc(`${f.c}/cash_movements/${id}`), {...oldHead, id, currency: "JOD", moneyScale: 3, createdAt: FieldValue.serverTimestamp()});
    batch.set(balanceRef, {...balance, currency: "JOD", moneyScale: 3, lastMovementId: id, updatedAt: FieldValue.serverTimestamp()});
  }
  batch.update(db.doc(f.paths.policy), {legacyCurrencyBindingId: FieldValue.delete()});await batch.commit();
  assert.equal((await f.prepare()).evidence.context.legacyCurrencyBindingRevisionId, null);
});

test("authentication is rechecked on every attempt and cannot be supplied by evidence", async () => {
  const f = await fixture(), e = (await f.prepare()).evidence;
  await assert.rejects(() => prepare(db, undefined, f.input, e), code("unauthenticated"));
  for (const uid of ["missing-synthetic-admin", f.rep]) await assert.rejects(() => f.prepare({}, e, uid), code("permission-denied"));
  const ref = db.doc(`users/${f.admin}`), original = (await ref.get()).data();
  for (const change of [{companyId: "foreign"}, {active: false}, {approvalStatus: "pending"}, {role: "customer"}, {companyId: ""}]) {
    await ref.set({...original, ...change});
    await assert.rejects(() => f.prepare({}, e), code("permission-denied"));
  }
  await ref.set(original);
  const repRef = db.doc(`users/${f.rep}`), rep = (await repRef.get()).data();
  for (const change of [{active: false}, {approvalStatus: "pending"}, {role: "admin"}, {companyId: "foreign"}, {uid: "forged"}]) {
    await repRef.set({...rep, ...change});
    await assert.rejects(() => f.prepare(), code("failed-precondition"));
  }
  await noJournal(f);
});

test("pending transaction performs bounded document reads, no queries and no writes", async () => {
  const f = await fixture(), counts = {get: 0, getAll: 0}, paths = [];
  const database = wrapped((t, cb) => cb(proxy(t, {
    get(ref) {assert.equal(typeof ref.path, "string");counts.get++;paths.push(ref.path);return t.get(ref);},
    getAll(...refs) {counts.getAll++;for (const ref of refs) {assert.equal(typeof ref.path, "string");paths.push(ref.path);}return t.getAll(...refs);},
    create() {assert.fail("create forbidden");}, set() {assert.fail("set forbidden");}, update() {assert.fail("update forbidden");}, delete() {assert.fail("delete forbidden");},
  })));
  const r = await f.prepare({}, undefined, f.admin, database);
  assert.equal(counts.get, 1);assert.equal(paths.length, 23);assert.equal(new Set(paths).size, 22);
  assert.equal(counts.getAll, 11);assert.equal(r.evidence.versions.length, 22);
});

test("SDK transaction abort retries rebuild local reads and preserve deterministic pending evidence", async () => {
  const f = await fixture(), prior = (await f.prepare()).evidence, before = await financialSnapshot(f);let attempts = 0;
  const database = wrapped(async (t, cb) => {attempts++;const r = await cb(t);if (attempts === 1) throw Object.assign(new Error("synthetic retry"), {code: 10});return r;});
  assert.deepEqual((await f.prepare({}, prior, f.admin, database)).evidence, prior);
  assert.equal(attempts, 2);assert.deepEqual(await financialSnapshot(f), before);
});

test("caller mutation cannot change reviewed evidence or the request between owning-transaction attempts", async () => {
  const f = await fixture(), original = (await f.prepare()).evidence, expected = clone(original), input = clone(f.input);let attempts = 0;
  const database = wrapped(async (t, cb) => {
    attempts++;const r = await cb(t);
    if (attempts === 1) {
      expected.economics.amountUnits = "999";input.amount = "2.345";input.settlementDate.nanoseconds = 5;
      throw Object.assign(new Error("synthetic retry with caller mutation"), {code: 10});
    }return r;
  });
  assert.deepEqual((await prepare(database, f.admin, input, expected)).evidence, original);
  assert.equal(attempts, 2);
  const callerOwned = clone(original);
  const r = await db.runTransaction(t => {
    const pending = inTransaction(t, db, f.admin, f.input, callerOwned);
    callerOwned.timestamps.sourceCommittedAt = plainTime(date);
    return pending;
  });
  assert.deepEqual(r.evidence, original);
});

test("pending exact amounts conserve cash and journal balance including smallest units and full cash exhaustion", async () => {
  const f = await fixture(), before = await financialSnapshot(f);
  for (const units of [1n, 2n, 100n, 1234n, 69988n]) {
    const amount = `${units / 1000n}.${String(units % 1000n).padStart(3, "0")}`;
    const e = (await f.prepare({amount})).evidence;
    assert.equal(e.economics.lines.reduce((a, l) => a + BigInt(l.debitUnits) - BigInt(l.creditUnits), 0n), 0n);
    assert.equal(e.cashEffects.reduce((a, l) => a + BigInt(l.balanceBeforeUnits), 0n),
      e.cashEffects.reduce((a, l) => a + BigInt(l.balanceAfterUnits), 0n));
    assert.equal(BigInt(e.cashEffects[0].balanceAfterUnits), 69988n - units);
  }
  assert.deepEqual(await financialSnapshot(f), before);
});

test("pending rejects legacy arithmetic divergence even when every operand and exact result is representable", async () => {
  const f = await fixture(), balance = (await db.doc(f.paths.repBalance).get()).data();
  const head = (await db.doc(f.paths.repHead).get()).data(), id = "synthetic-large-cash-head", amount = 9007199254740.99;
  const batch = db.batch();
  // Synthetic boundary state with genuine atomic SDK witnesses, not a balance repair.
  batch.create(db.doc(`${f.c}/cash_movements/${id}`), {...head, id, direction: "in", amount, balanceBefore: 0, balanceAfter: amount,
    createdAt: FieldValue.serverTimestamp()});
  batch.set(db.doc(f.paths.repBalance), {...balance, amount, lastMovementId: id, updatedAt: FieldValue.serverTimestamp()});
  await batch.commit();const before = await financialSnapshot(f);
  await assert.rejects(() => f.prepare({amount: "0.040"}), error => {
    assert.equal(error.code, "failed-precondition");assert.match(error.message, /arithmetic compatibility/);return true;
  });
  assert.equal((await f.prepare({amount: "0.010"})).evidence.cashEffects[0].balanceAfterUnits, "9007199254740980");
  assert.deepEqual(await financialSnapshot(f), before);await noJournal(f);
});

test("creating even an inactive maintenance lock changes the observed configuration version", async () => {
  const f = await fixture(), e = (await f.prepare()).evidence;
  await db.doc(f.paths.lock).create({active: false});
  await assert.rejects(() => f.prepare({}, e), code("failed-precondition"));
  assert.notEqual((await f.prepare()).evidence.configurationDigest, e.configurationDigest);
});

test("retry after a concurrent cash commit rejects stale expected evidence without writing", async () => {
  const f = await fixture(), prior = (await f.prepare()).evidence;let attempts = 0, advancement;
  const database = wrapped(async (t, cb) => {
    if (advancement) await advancement;
    attempts++;const r = await cb(t);
    if (attempts === 1) {advancement = f.advance();throw Object.assign(new Error("synthetic contention"), {code: 10});}return r;
  });
  await assert.rejects(() => f.prepare({}, prior, f.admin, database), code("failed-precondition"));
  assert.equal(attempts, 2);await noJournal(f);
  assert.deepEqual((await f.prepare()).evidence.positions.map(p => p.amountUnits), ["68988", "51345"]);
});

test("caller-owned transaction validates before any writes and rolls back a read-after-write caller", async () => {
  const f = await fixture(), marker = db.doc(`${f.c}/synthetic_probes/bad-order`), before = await financialSnapshot(f);
  await assert.rejects(() => db.runTransaction(async t => {t.create(marker, {synthetic: true});await inTransaction(t, db, f.admin, f.input);}), /all reads.*before.*writes/i);
  assert.equal((await marker.get()).exists, false);assert.deepEqual(await financialSnapshot(f), before);
  // Generic probe demonstrates caller-owned composition; it is not financial persistence.
  const good = db.doc(`${f.c}/synthetic_probes/good-order`);
  const e = await db.runTransaction(async t => {const r = await inTransaction(t, db, f.admin, f.input);t.create(good, {digest: r.evidence.preflightDigest});return r.evidence;});
  assert.equal((await good.get()).data().digest, e.preflightDigest);await noJournal(f);
});

test("existing writer subsequently commits the same economics using genuine metadata; old pending clocks stay unknown", async () => {
  const f = await fixture(), pending = (await f.prepare()).evidence;
  const posted = await post(db, f.admin, f.company, f.input.idempotencyKey, {salesRepId: f.rep, amount: 1.234, settlementDate: date, notes: f.input.notes});
  const committed = await preflightSettlementTransaction(db, f.admin, {companyId: f.company, settlementId: posted.settlementId});
  assert.equal(committed.intent.id, pending.id);assert.deepEqual(committed.intent.lines, pending.economics.lines);
  assert.deepEqual(committed.positions.map(p => p.amountUnits), pending.cashEffects.map(p => p.balanceAfterUnits));
  const snapshot = await db.doc(pending.targets.settlement).get();
  assert.deepEqual(committed.timestamps.sourceCommittedAt, plainTime(snapshot.createTime));
  assert.deepEqual(committed.timestamps.sourceRecordedAt, plainTime(snapshot.data().postedAt));
  assert.equal(pending.timestamps.sourceCommittedAt, null);assert.equal(pending.timestamps.journalCommittedAt, null);
  await assert.rejects(() => f.prepare({}, pending), code("already-exists"));
  const beforeReplay = await financialSnapshot(f);
  assert.equal((await post(db, f.admin, f.company, f.input.idempotencyKey, {salesRepId: f.rep, amount: 1.234,
    settlementDate: new Timestamp(date.seconds + 1, 0), notes: "Legacy replay behavior remains unchanged"})).alreadyPosted, true);
  assert.deepEqual(await financialSnapshot(f), beforeReplay);await noJournal(f);
});

test("racing a pending reader with the existing writer never posts a journal or duplicates cash", async () => {
  const f = await fixture(), results = await Promise.allSettled([f.prepare(), post(db, f.admin, f.company, f.input.idempotencyKey,
    {salesRepId: f.rep, amount: 1.234, settlementDate: date, notes: f.input.notes})]);
  assert.equal(results[1].status, "fulfilled");
  if (results[0].status === "rejected") assert.equal(results[0].reason.code, "already-exists");
  assert.equal((await db.collection(`${f.c}/settlements`).get()).size, 2);
  assert.equal((await db.doc(f.paths.repBalance).get()).data().amount, 68.754);
  assert.equal((await db.doc(f.paths.companyBalance).get()).data().amount, 51.579);
  await assert.rejects(() => f.prepare(), code("already-exists"));await noJournal(f);
});

test("pure shared journal economics validates canonical units and never requires future committed clocks", async () => {
  const f = await fixture(), e = (await f.prepare()).evidence;
  const input = {companyId: f.company, bookId: f.bookId, settlementId: e.source.id, salesRepId: f.rep,
    amountUnits: "1234", policy: e.economics.policy, mappings: e.economics.lines.map(l => l.account)};
  assert.deepEqual(buildSettlementJournalEconomics(input), e.economics);
  assert.notEqual(buildSettlementJournalEconomics({...input, bookId: "other-book", policy: {...input.policy, bookId: "other-book"},
    mappings: input.mappings.map(m => ({...m, bookId: "other-book"}))}).id, e.id);
  for (const amountUnits of ["0", "-1", "01", "1.0", "1e3", "1".repeat(31), 1234]) assert.throws(() => buildSettlementJournalEconomics({...input, amountUnits}), code("invalid-argument"));
  assert.throws(() => buildSettlementJournalEconomics(undefined), code("invalid-argument"));
  for (const file of ["record_cash_settlement.ts", "../index.ts"]) {
    assert.doesNotMatch(readFileSync(join(__dirname, "../src/trusted", file), "utf8"), /pendingSettlementEvidence|preparePendingSettlement|settlement_pending_evidence|buildSettlementJournalEconomics/);
  }
});
