"use strict";
const assert = require("node:assert/strict");
const {test, after} = require("node:test");
const {writeFileSync} = require("node:fs");
if (process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8192" || process.env.FIREBASE_AUTH_EMULATOR_HOST !== "127.0.0.1:9098") throw new Error("Isolated Phase 2B-12 emulators required.");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {createSettlementTransport, SETTLEMENT_TRANSPORT_LIMITS: limits} = require("../lib/trusted/settlement_transport");
const {verifySettlementBreakdownDetailPages} = require("../lib/trusted/settlement_breakdown_presentation");
const {breakdownFixture} = require("./helpers/settlement_breakdown_fixture");
const {volumeFixture} = require("./helpers/settlement_volume_fixture");
const app = initializeApp({projectId: "demo-fatoora-phase2b7"}, "phase2b12-transport-tests"), db = getFirestore(app), benchmarks = [];
after(async () => {if (benchmarks.length) writeFileSync("../output/phase2b12-performance.json", JSON.stringify({synthetic: true, benchmarks}, null, 2));await deleteApp(app);});
const code = value => error => {assert.equal(error.code, value, error.stack);return true;};
const scope = f => ({companyId: f.companyId, salesRepId: f.rep, settlementId: f.currentId});
const principal = f => ({uid: f.admin, authTime: Math.floor(Date.now() / 1000)});
const start = f => ({schemaVersion: 1, action: "start", ...scope(f)});
const next = token => ({schemaVersion: 1, action: "page", token});
const authState = () => ({disabled: false, revoked: 0, calls: 0, async getUser(uid) {this.calls++;return {uid, disabled: this.disabled, tokensValidAfterTime: new Date(this.revoked).toUTCString()};}});
async function fixture(options) {const f = await volumeFixture(db, 65, options);return f;}

test("strict authenticated scope, immutable page roots, exact assembly and idempotent lost acknowledgements", async () => {
  const f = await fixture({mixed: true}), svc = createSettlementTransport(db, authState()), who = principal(f);
  const first = await svc.request(who, start(f));assert.equal(first.kind, "page");assert.equal(first.page.pageCount, 2);
  assert.equal(first.provenance, "authenticated_firebase");assert.equal(first.exportToken, null);
  assert.ok(!JSON.stringify(first).includes('"readWitness"'));assert.ok(!JSON.stringify(first).includes('"observation"'));
  const second = await svc.request(who, next(first.nextToken)), retry = await svc.request(who, next(first.nextToken));
  assert.deepEqual(retry, second);assert.equal(first.page.snapshotDigest, second.page.snapshotDigest);
  const result = verifySettlementBreakdownDetailPages([first.page, second.page]);assert.equal(result.totals.remainingUnits, f.remainingUnits);
  const permission = await svc.request(who, {schemaVersion: 1, action: "authorizePdf", token: second.exportToken});
  assert.equal(permission.evidenceDigest, first.page.evidenceDigest);assert.ok(permission.validUntilMillis <= Date.now() + 15000);
  assert.throws(() => {first.page.rows[0].sourceNumber = "forged";}, TypeError);
});

for (const mutation of ["source", "insert", "delete", "balance", "configuration", "target"]) test(`changed ${mutation} evidence invalidates all following pages`, async () => {
  const f = await fixture(), svc = createSettlementTransport(db, authState()), who = principal(f), first = await svc.request(who, start(f));
  if (mutation === "source") await f.ref("invoices", "volume-000000").update({invoiceNumber: "MODIFIED"});
  if (mutation === "insert") await f.ref("expenses", "new-pending").create({id: "new-pending", companyId: f.companyId, status: "pending"});
  if (mutation === "delete") await f.ref("invoices", "volume-000000").delete();
  if (mutation === "balance") await f.ref("cash_balances", `rep_${f.rep}`).update({amount: 100});
  if (mutation === "configuration") await db.doc(f.b).update({currency: "USD"});
  if (mutation === "target") await f.ref("settlements", f.currentId).update({settlementNumber: "MODIFIED"});
  await assert.rejects(svc.request(who, next(first.nextToken)), code("failed-precondition"));
  await assert.rejects(svc.request(who, next(first.nextToken)), code("failed-precondition"));
});

for (const revoke of ["role", "inactive", "approval", "company", "disabled", "token"]) test(`current ${revoke} revocation denies cached evidence`, async () => {
  const f = await fixture(), auth = authState(), svc = createSettlementTransport(db, auth), who = principal(f), first = await svc.request(who, start(f));
  if (revoke === "role") await db.doc(`users/${f.admin}`).update({role: "sales_rep"});
  if (revoke === "inactive") await db.doc(`users/${f.admin}`).update({active: false});
  if (revoke === "approval") await db.doc(`users/${f.admin}`).update({approvalStatus: "pending"});
  if (revoke === "company") await db.doc(f.c).update({active: false});
  if (revoke === "disabled") auth.disabled = true;
  if (revoke === "token") auth.revoked = Date.now() + 10000;
  await assert.rejects(svc.request(who, next(first.nextToken)), code("permission-denied"));
  assert.equal(svc.statistics().sessions, 0);
});

test("invalid tokens, wrong user/login, extra fields, cross-company and representative claims fail closed", async () => {
  const f = await fixture(), svc = createSettlementTransport(db, authState()), who = principal(f), first = await svc.request(who, start(f));
  for (const token of ["x", first.nextToken.slice(0, -4) + "AAAA", first.nextToken + "=", "a".repeat(4097)]) await assert.rejects(svc.request(who, next(token)), code("failed-precondition"));
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_", last = first.nextToken.at(-1);
  await assert.rejects(svc.request(who, next(first.nextToken.slice(0, -1) + alphabet[alphabet.indexOf(last) ^ 1])), code("failed-precondition"));
  await assert.rejects(svc.request({...who, uid: f.other}, next(first.nextToken)), code("failed-precondition"));
  await assert.rejects(svc.request({...who, authTime: who.authTime + 1}, next(first.nextToken)), code("failed-precondition"));
  await assert.rejects(svc.request(who, {...next(first.nextToken), role: "admin"}), code("invalid-argument"));
  const other = createSettlementTransport(db, authState());
  await assert.rejects(other.request(who, {...start(f), companyId: "other-company"}), code("permission-denied"));
  const third = createSettlementTransport(db, authState());
  await assert.rejects(third.request(who, {...start(f), salesRepId: f.other}), code("permission-denied"));
});

test("expired and cold-instance sessions never rebuild a snapshot silently", async () => {
  const f = await fixture(), who = principal(f);let now = Date.now();
  const svc = createSettlementTransport(db, authState(), () => now), first = await svc.request(who, start(f));
  now += limits.ttlMillis;
  await assert.rejects(svc.request(who, next(first.nextToken)), code("failed-precondition"));
  await assert.rejects(createSettlementTransport(db, authState()).request(who, next(first.nextToken)), code("failed-precondition"));
});

test("unknown historical opening stays blocked and cannot leak verified fixture totals", async () => {
  const f = await breakdownFixture(db, {opening: false});f.currentId = (await f.settle("unknown-opening", 1)).settlementId;
  const svc = createSettlementTransport(db, authState()), first = await svc.request(principal(f), start(f));
  assert.equal(first.page.status, "blocked");assert.equal(first.page.totals, null);assert.equal(first.page.opening.amountUnits, null);
  writeFileSync("../test/fixtures/settlement_transport_blocked_emulator.json", JSON.stringify({provenance: "synthetic_emulator_capture",
    companyId: f.companyId, salesRepId: f.rep, settlementId: f.currentId, pages: [first.page]}, null, 2));
});

test("concurrent requests reject contention and replay flooding has a bounded cost", async () => {
  const f = await fixture(), auth = authState(), svc = createSettlementTransport(db, auth), who = principal(f), first = await svc.request(who, start(f));
  const pending = svc.request(who, next(first.nextToken));
  await assert.rejects(svc.request(who, next(first.nextToken)), code("aborted"));await pending;
  let rejected = false;
  for (let i = 0; i < 70; i++) {
    try {await svc.request(who, next("invalid"));} catch (e) {if (e.code === "resource-exhausted") {rejected = true;break;}}
  }
  assert.ok(rejected);assert.ok(svc.statistics().chargedReadWork < 250000);
});

test("final authorization catches revocation after version validation", async () => {
  const f = await fixture(), auth = authState(), svc = createSettlementTransport(db, auth), who = principal(f), first = await svc.request(who, start(f));
  const original = auth.getUser.bind(auth);let count = 0;
  auth.getUser = async uid => {if (++count === 2) await db.doc(`users/${f.admin}`).update({active: false});return original(uid);};
  await assert.rejects(svc.request(who, next(first.nextToken)), code("permission-denied"));
});

for (const count of [1000, 3000]) test(`bounded ${count}-movement transport preserves page/PDF economics`, async t => {
  const f = await volumeFixture(db, count, {mixed: true}), svc = createSettlementTransport(db, authState()), who = principal(f), began = performance.now();
  let result = await svc.request(who, start(f));const firstMillis = performance.now() - began, pages = [result.page], at = performance.now();
  while (result.nextToken) {result = await svc.request(who, next(result.nextToken));pages.push(result.page);}
  assert.equal(verifySettlementBreakdownDetailPages(pages).totals.remainingUnits, f.remainingUnits);
  await svc.request(who, {schemaVersion: 1, action: "authorizePdf", token: result.exportToken});
  const measurement = {movements: count, pages: pages.length, firstPageMillis: Math.round(firstMillis), remainingPagesAndExportMillis: Math.round(performance.now() - at), ...svc.statistics()};
  benchmarks.push(measurement);t.diagnostic(JSON.stringify(measurement));
});

test("real Auth emulator ID token works through callable protocol; missing auth, replay and revocation fail", async () => {
  const f = await fixture({mixed: true}), auth = getAuth(app), email = `${f.admin}@example.test`, password = "Synthetic-Phase2B12-123!";
  await auth.createUser({uid: f.admin, email, password});
  const signedIn = await fetch("http://127.0.0.1:9098/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=synthetic", {
    method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({email, password, returnSecureToken: true}),
  }).then(r => r.json());assert.ok(signedIn.idToken);
  const call = async (data, token) => fetch("http://127.0.0.1:5005/demo-fatoora-phase2b7/us-central1/getSettlementBreakdown", {
    method: "POST", headers: {"content-type": "application/json", ...(token ? {authorization: `Bearer ${token}`} : {})}, body: JSON.stringify({data}),
  }).then(r => r.json());
  assert.equal((await call(start(f))).error.status, "UNAUTHENTICATED");
  const parts = signedIn.idToken.split("."), foreignClaims = JSON.parse(Buffer.from(parts[1], "base64url").toString());
  foreignClaims.aud = "other-demo-project";foreignClaims.iss = "https://securetoken.google.com/other-demo-project";
  const foreignToken = `${parts[0]}.${Buffer.from(JSON.stringify(foreignClaims)).toString("base64url")}.${parts[2]}`;
  assert.ok(["UNAUTHENTICATED", "PERMISSION_DENIED"].includes((await call(start(f), foreignToken)).error.status));
  const began = performance.now();
  const first = await call(start(f), signedIn.idToken);assert.ok(first.result, JSON.stringify(first));
  assert.equal(first.result.page.status, "verified_cash_reconstruction");
  const final = await call(next(first.result.nextToken), signedIn.idToken);assert.ok(final.result, JSON.stringify(final));
  const permit = await call({schemaVersion: 1, action: "authorizePdf", token: final.result.exportToken}, signedIn.idToken);assert.equal(permit.result.kind, "pdf_permission");
  writeFileSync("../output/phase2b12-callable-performance.json", JSON.stringify({synthetic: true, authProvider: "real_auth_emulator", pages: 2,
    milliseconds: Math.round(performance.now() - began), responseBytes: Buffer.byteLength(JSON.stringify([first.result, final.result, permit.result]))}, null, 2));
  // Persist only immutable synthetic wire evidence, never auth/session tokens.
  await auth.updateUser(f.admin, {disabled: true});
  assert.equal((await call(next(first.result.nextToken), signedIn.idToken)).error.status, "PERMISSION_DENIED");
  await auth.updateUser(f.admin, {disabled: false});
  await new Promise(resolve => setTimeout(resolve, 1100));
  const relogin = await fetch("http://127.0.0.1:9098/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=synthetic", {
    method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({email, password, returnSecureToken: true}),
  }).then(r => r.json());
  const refreshed = await call(start(f), relogin.idToken);assert.ok(refreshed.result, JSON.stringify(refreshed));
  await new Promise(resolve => setTimeout(resolve, 1100));await auth.revokeRefreshTokens(f.admin);
  assert.equal((await call(next(refreshed.result.nextToken), relogin.idToken)).error.status, "PERMISSION_DENIED");
  const presenter = `${f.admin}-presentation`;
  await auth.createUser({uid: presenter, email: `${presenter}@example.test`, password});
  await db.doc(`users/${presenter}`).create({uid: presenter, companyId: f.companyId, name: "Synthetic presentation reviewer", role: "admin", active: true, approvalStatus: "approved"});
  writeFileSync("../test/fixtures/settlement_transport_emulator.json", JSON.stringify({provenance: "synthetic_emulator_capture", companyId: f.companyId,
    salesRepId: f.rep, settlementId: f.currentId, viewerUid: presenter, pages: [first.result.page, final.result.page]}, null, 2));
});

test("oversized pages are rejected before any partial financial response", async () => {
  const f = await volumeFixture(db, 65, {participantName: "م".repeat(2048)}), svc = createSettlementTransport(db, authState());
  await assert.rejects(svc.request(principal(f), start(f)), code("resource-exhausted"));assert.equal(svc.statistics().sessions, 0);
});

test("PDF export rechecks changed evidence after complete detail delivery", async () => {
  const f = await fixture(), svc = createSettlementTransport(db, authState()), who = principal(f);
  const first = await svc.request(who, start(f)), final = await svc.request(who, next(first.nextToken));
  await f.ref("invoices", "volume-000001").update({invoiceNumber: "AFTER-DETAILS"});
  await assert.rejects(svc.request(who, {schemaVersion: 1, action: "authorizePdf", token: final.exportToken}), code("failed-precondition"));
});

test("incomplete company coverage returns a notice with no pages, tokens or assumed opening", async () => {
  const f = await breakdownFixture(db);f.currentId = (await f.settle("coverage-cap", 1)).settlementId;
  for (let offset = 0; offset < 16001; offset += 400) {
    const batch = db.batch();
    for (let i = offset; i < Math.min(offset + 400, 16001); i++) {
      const id = `draft-${i}`;batch.create(f.ref("invoices", id), {id, companyId: f.companyId, invoiceStatus: "draft", financialPosted: false});
    }
    await batch.commit();
  }
  const svc = createSettlementTransport(db, authState()), value = await svc.request(principal(f), start(f));
  assert.deepEqual(Object.keys(value).sort(), ["schemaVersion", "kind", "provenance", "companyId", "salesRepId", "settlementId", "reason"].sort());
  assert.equal(value.kind, "incomplete");assert.equal(svc.statistics().sessions, 0);
});

test("pending starts retain their ownership lock after a conflicting start", async () => {
  const f = await fixture(), auth = authState();let now = Date.now(), release;
  const gate = new Promise(resolve => {release = resolve;}), original = auth.getUser.bind(auth);
  auth.getUser = async uid => {await gate;return original(uid);};
  const svc = createSettlementTransport(db, auth, () => now), who = principal(f), pending = svc.request(who, start(f));
  await assert.rejects(svc.request(who, start(f)), code("aborted"));
  now += 60001;
  await assert.rejects(svc.request(who, start(f)), code("aborted"));
  release();await pending;assert.equal(svc.statistics().sessions, 1);
});

test("transport transactions leave synthetic source and balance records unchanged", async () => {
  const f = await fixture(), svc = createSettlementTransport(db, authState()), who = principal(f);
  const versions = async () => {
    const result = [];
    for (const c of ["cash_movements","invoices","receipts","sales_returns","expenses","settlements","cash_balances"]) {
      const snap = await db.collection(`${f.c}/${c}`).get();
      result.push(...snap.docs.map(d => [d.ref.path, d.createTime.seconds, d.createTime.nanoseconds, d.updateTime.seconds, d.updateTime.nanoseconds, d.data()]));
    }
    return JSON.stringify(result);
  };
  const before = await versions(), first = await svc.request(who, start(f)), last = await svc.request(who, next(first.nextToken));
  await svc.request(who, {schemaVersion: 1, action: "authorizePdf", token: last.exportToken});
  assert.equal(await versions(), before);
});

test("resolved transaction transport is guarded before any independent read", async () => {
  const f = await fixture();let reads = 0;
  const foreign = {projectId: "forbidden-project", databaseId: "(default)", _settings: {servicePath: "127.0.0.1", ssl: false, port: 8192}};
  const database = new Proxy(db, {get(target, property) {
    if (property === "runTransaction") return (fn, options) => target.runTransaction(tx => fn(new Proxy(tx, {get(raw, key) {
      if (key === "_firestore") return foreign;
      if (key === "get" || key === "getAll") return () => {reads++;throw new Error("Must reject before read");};
      const value = Reflect.get(raw, key);return typeof value === "function" ? value.bind(raw) : value;
    }})), options);
    const value = Reflect.get(target, property);return typeof value === "function" ? value.bind(target) : value;
  }});
  await assert.rejects(createSettlementTransport(database, authState()).request(principal(f), start(f)), code("failed-precondition"));
  assert.equal(reads, 0);
});
