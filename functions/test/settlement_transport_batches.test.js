"use strict";
const assert = require("node:assert/strict"), {test, after} = require("node:test");
if (process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8192") throw Error("Isolated emulator required.");
const {initializeApp, deleteApp} = require("firebase-admin/app"), {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {createSettlementTransport, SETTLEMENT_TRANSPORT_LIMITS: limits} = require("../lib/trusted/settlement_transport");
const {verifySettlementBreakdownDetailPages} = require("../lib/trusted/settlement_breakdown_presentation");
const {volumeFixture} = require("./helpers/settlement_volume_fixture"), {breakdownFixture} = require("./helpers/settlement_breakdown_fixture");
const {profiledDatabase, measure} = require("./helpers/settlement_transport_profile");
const {createSettlementFixture} = require("./helpers/settlement_fixture");
const app = initializeApp({projectId: "demo-fatoora-phase2b7"}, "phase2b13-batches"), db = getFirestore(app);
after(() => deleteApp(app));
const auth = () => ({disabled: false, revoked: 0, calls: 0, async getUser(uid) {this.calls++;return {uid, disabled: this.disabled, tokensValidAfterTime: new Date(this.revoked).toUTCString()};}});
const principal = f => ({uid: f.admin, authTime: Math.floor(Date.now() / 1000)});
const start = f => ({schemaVersion: 2, action: "start", companyId: f.companyId, salesRepId: f.rep, settlementId: f.currentId});
const page = token => ({schemaVersion: 2, action: "page", token});
const last = r => r.pages.at(-1);
const code = expected => e => {assert.equal(e.code, expected, e.stack);return true;};
const fixture = () => volumeFixture(db, 400, {mixed: true});

test("one verified snapshot serves bounded existing DTO batches and exact PDF, with deterministic group retry", async () => {
  const f = await fixture(), svc = createSettlementTransport(profiledDatabase(db), auth()), who = principal(f);
  let r = await svc.request(who, start(f));const first = r, pages = r.pages.map(v => v.page);
  assert.ok(r.pages.length > 1 && r.pages.length <= 6);assert.ok(last(r).nextToken);
  assert.throws(() => {r.pages[0].page.rows[0].sourceNumber = "forged";}, TypeError);
  const input = page(last(r).nextToken), next = await measure(() => svc.request(who, input));r = next.result;
  assert.deepEqual(await svc.request(who, input), r);
  assert.equal(next.metrics.queries, 6);assert.ok(next.metrics.documentReads < 1000);
  pages.push(...r.pages.map(v => v.page));
  while (last(r).nextToken) {r = await svc.request(who, page(last(r).nextToken));pages.push(...r.pages.map(v => v.page));}
  assert.equal(verifySettlementBreakdownDetailPages(pages).totals.remainingUnits, f.remainingUnits);
  const permit = await svc.request(who, {schemaVersion: 2, action: "authorizePdf", token: last(r).exportToken});
  assert.equal(permit.evidenceDigest, first.pages[0].page.evidenceDigest);assert.ok(permit.validUntilMillis <= Date.now() + 15000);
  assert.ok(Buffer.byteLength(JSON.stringify(first)) <= limits.responseBytes);
  assert.ok(!JSON.stringify(first).includes('"readWitness"'));
});

test("immutable Unicode evidence chooses byte-bounded groups without truncating any detail page", async () => {
  const f = await volumeFixture(db, 400, {mixed: true, participantName: "\u0645".repeat(128)});
  const svc = createSettlementTransport(db, auth()), who = principal(f), pages = [];
  let r = await svc.request(who, start(f));assert.ok(r.pages.length < limits.deliveryPages);
  for (;;) {
    assert.ok(Buffer.byteLength(JSON.stringify(r)) <= limits.responseBytes);
    assert.equal(r.firstPageIndex, pages.length);assert.equal(r.pageCount, r.pages.length);
    pages.push(...r.pages.map(p => p.page));
    if (!last(r).nextToken) break;r = await svc.request(who, page(last(r).nextToken));
  }
  assert.equal(verifySettlementBreakdownDetailPages(pages).rows.length, pages[0].rowCount);
});

for (const mutation of ["insert-before", "insert-after", "empty-insert", "delete", "replace-same-count", "rewrite-restored", "delete-recreate", "head", "configuration", "target", "missing-witness"]) {
  test(`batch continuation rejects ${mutation} financial evidence`, async () => {
    const f = await fixture(), svc = createSettlementTransport(db, auth()), who = principal(f), r = await svc.request(who, start(f));
    const ref = f.ref("invoices", "volume-000000"), original = (await ref.get()).data();
    if (mutation.startsWith("insert-")) await f.ref("invoices", mutation === "insert-before" ? "000-before" : "zzz-after").create({id: "extra", companyId: f.companyId});
    if (mutation === "empty-insert") await f.ref("expenses", "new").create({id: "new", companyId: f.companyId});
    if (mutation === "delete" || mutation === "delete-recreate" || mutation === "replace-same-count") await ref.delete();
    if (mutation === "replace-same-count") await f.ref("invoices", "different").create(original);
    if (mutation === "rewrite-restored") {await ref.update({invoiceNumber: "ALTERED"});await ref.set(original);}
    if (mutation === "delete-recreate") await ref.create(original);
    if (mutation === "head") await f.ref("cash_balances", `rep_${f.rep}`).update({amount: 0});
    if (mutation === "configuration") await db.doc(f.b).update({currency: "USD"});
    if (mutation === "target") await f.ref("settlements", f.currentId).update({settlementNumber: "ALTERED"});
    if (mutation === "missing-witness") await f.ref("maintenance_locks", "cash_reconciliation").create({active: false});
    await assert.rejects(svc.request(who, page(last(r).nextToken)), code("failed-precondition"));
    assert.equal(svc.statistics().sessions, 0);
  });
}

for (const reason of ["disabled", "revoked", "profile", "company"]) test(`batch checks ${reason} before serving cached pages`, async () => {
  const f = await fixture(), provider = auth(), svc = createSettlementTransport(db, provider), who = principal(f), r = await svc.request(who, start(f));
  if (reason === "disabled") provider.disabled = true;
  if (reason === "revoked") provider.revoked = Date.now() + 2000;
  if (reason === "profile") await db.doc(`users/${f.admin}`).update({approvalStatus: "pending"});
  if (reason === "company") await db.doc(`companies/${f.companyId}`).update({active: false});
  await assert.rejects(svc.request(who, page(last(r).nextToken)), code("permission-denied"));assert.equal(svc.statistics().sessions, 0);
});

test("partial/mixed-version/middle-group tokens, tampering, expiry and cold loss never reconstruct a session", async () => {
  const f = await fixture(), who = principal(f);
  for (const reason of ["middle", "version", "tamper", "expired", "cold"]) {
    let now = Date.now();const svc = createSettlementTransport(db, auth(), () => now), r = await svc.request(who, start(f));
    let input = page(reason === "middle" ? r.pages[0].nextToken : last(r).nextToken);
    if (reason === "version") input.schemaVersion = 1;
    if (reason === "tamper") input.token = `x${input.token.slice(1)}`;
    if (reason === "expired") now += limits.ttlMillis;
    const target = reason === "cold" ? createSettlementTransport(db, auth()) : svc;
    await assert.rejects(target.request(who, input), code("failed-precondition"));
  }
});

test("concurrent same-session requests serialize, final role revocation clears a completed batch", async () => {
  const f = await fixture(), provider = auth(), svc = createSettlementTransport(db, provider), who = principal(f), r = await svc.request(who, start(f));
  const pending = svc.request(who, page(last(r).nextToken));
  await assert.rejects(svc.request(who, page(last(r).nextToken)), code("aborted"));await pending;
  const original = provider.getUser.bind(provider);let calls = 0;
  provider.getUser = async uid => {if (++calls === 2) await db.doc(`users/${f.admin}`).update({active: false});return original(uid);};
  await assert.rejects(svc.request(who, page(last(r).nextToken)), code("permission-denied"));
});

function altered(db, transform) {
  return new Proxy(db, {get(target, prop) {
    if (prop === "runTransaction") return (fn, options) => target.runTransaction(tx => fn(new Proxy(tx, {get(raw, p) {
      if (p === "get") return async q => transform(await raw.get(q), q);
      const v = Reflect.get(raw, p, raw);return typeof v === "function" ? v.bind(raw) : v;
    }})), options);
    const v = Reflect.get(target, prop, target);return typeof v === "function" ? v.bind(target) : v;
  }});
}
for (const corruption of ["partial", "duplicate", "read-time"]) test(`metadata coverage rejects ${corruption} SDK result`, async () => {
  const f = await fixture();let enabled = false;
  const database = altered(db, (r, q) => {
    if (!enabled || q.path || q.query || !r.docs?.length) return r;
    return new Proxy(r, {get(target, p) {
      if (corruption === "partial" && p === "docs") return target.docs.slice(1);
      if (corruption === "duplicate" && p === "docs") return [target.docs[0], ...target.docs.slice(0, -1)];
      if (corruption === "read-time" && p === "readTime") return Timestamp.fromMillis(1);
      const v = Reflect.get(target, p, target);return typeof v === "function" ? v.bind(target) : v;
    }});
  });
  const svc = createSettlementTransport(database, auth()), who = principal(f), r = await svc.request(who, start(f));enabled = true;
  await assert.rejects(svc.request(who, page(last(r).nextToken)), code("failed-precondition"));
});

test("unknown opening remains blocked, and PDF permits do not certify incomplete history", async () => {
  const f = await breakdownFixture(db, {opening: false});f.currentId = (await f.settle("missing-opening", 1)).settlementId;
  const svc = createSettlementTransport(db, auth()), r = await svc.request(principal(f), start(f));
  assert.equal(r.pages[0].page.status, "blocked");assert.equal(r.pages[0].page.totals, null);
  assert.equal(r.pages[0].page.opening.amountUnits, null);
});

test("missing atomic cash evidence remains a witnessed absence and never produces certified totals", async () => {
  const f = await createSettlementFixture(db, Timestamp.fromDate(new Date("2026-08-05T12:00:00Z")));
  const expected = await f.review(), posted = await f.persist({}, expected);
  // Use the actual stored settlement references, never invent a financial link.
  const target = await db.doc(`${f.c}/settlements/${posted.result.settlementId}`).get();
  const missing = db.doc(`${f.c}/cash_movements/${target.data().repMovementId}`), original = (await missing.get()).data();
  assert.ok(original);await missing.delete();
  const scope = {companyId: f.company, rep: f.rep, currentId: posted.result.settlementId, admin: f.admin};
  const svc = createSettlementTransport(db, auth()), r = await svc.request(principal(scope), start(scope));
  assert.equal(r.pages[0].page.status, "blocked");assert.equal(r.pages[0].page.totals, null);
  await missing.create(original);
  await assert.rejects(svc.request(principal(scope), {schemaVersion: 2, action: "authorizePdf", token: last(r).exportToken}), code("failed-precondition"));
});

test("high-load malformed replay fails before any Firestore read, resource bounds stay unchanged", async () => {
  const f = await fixture(), svc = createSettlementTransport(profiledDatabase(db), auth()), who = principal(f);
  let exhausted = false;
  const measured = await measure(async () => {
    for (let i = 0; i < 140; i++) try {await svc.request(who, page("forged"));} catch (e) {
      if (e.code === "resource-exhausted") {exhausted = true;break;}assert.equal(e.code, "failed-precondition");
    }
    return {};
  });
  assert.ok(exhausted);assert.equal(measured.metrics.documentReads, 0);
  assert.equal(limits.sessionReadWork, 1000000);assert.equal(limits.responseBytes, 1048576);assert.equal(limits.ttlMillis, 300000);
});

test("two authorized sessions can work concurrently; a third cannot escape admission", async () => {
  const f = await fixture(), ids = [f.admin, `${f.admin}-2`, `${f.admin}-3`];
  for (const uid of ids.slice(1)) await db.doc(`users/${uid}`).create({uid, companyId: f.companyId, role: "admin", active: true, approvalStatus: "approved"});
  let release;const gate = new Promise(resolve => {release = resolve;});let entered = 0;
  const provider = {async getUser(uid) {entered++;await gate;return {uid};}}, svc = createSettlementTransport(db, provider);
  const who = uid => ({uid, authTime: Math.floor(Date.now() / 1000)});
  const a = svc.request(who(ids[0]), start(f)), b = svc.request(who(ids[1]), start(f));
  assert.equal(entered, 2);await assert.rejects(svc.request(who(ids[2]), start(f)), code("resource-exhausted"));
  release();const results = await Promise.all([a, b]);assert.equal(results.length, 2);assert.equal(svc.statistics().sessions, 2);
});

test("failed parallel metadata queries drain before releasing the request slot", {timeout: 30000}, async () => {
  const f = await fixture();let enabled = false, release, finished = false, calls = 0;
  const gate = new Promise(resolve => {release = resolve;});
  const database = altered(db, async (r, q) => {
    if (!enabled || q.path || q.query) return r;
    if (++calls === 1) throw new Error("synthetic query failure");
    await gate;return r;
  });
  const svc = createSettlementTransport(database, auth()), who = principal(f), first = await svc.request(who, start(f));enabled = true;
  const pending = svc.request(who, page(last(first).nextToken)).then(() => {throw Error("Unexpected financial response");}, e => {finished = true;assert.match(e.message, /synthetic query failure/);});
  try {
    const deadline = Date.now() + 10000;
    while (calls < 6 && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 5));
    assert.equal(calls, 6);assert.equal(finished, false);
  } finally {release();}
  await pending;
});
