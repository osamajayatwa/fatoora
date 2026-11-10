"use strict";
const {test, after} = require("node:test"), assert = require("node:assert/strict");
const {Firestore, Transaction} = require("firebase-admin/firestore");
const targetModule = require("../lib/trusted/settlement_read_target");
const {validateSettlementPilotControl: validate, createSettlementPilotAccess, SETTLEMENT_STAGING_APPS} = require("../lib/trusted/settlement_staging_access");
const {persistSettlementJournalTransaction, prepareSettlementJournalPersistence} = require("../lib/trusted/settlement_journal_persistence");
const {verifySettlementReadRuntime} = require("../lib/trusted/settlement_runtime_canary");
const project = targetModule.SETTLEMENT_STAGING_PROJECT, now = Date.now();
const principal = {uid: "synthetic-admin", authTime: Math.floor(now / 1000), appId: SETTLEMENT_STAGING_APPS[0]};
const control = () => ({schemaVersion: 1, enabled: true, companyId: "default_company", revision: "a".repeat(64),
  expiresAtMillis: now + 3600000, allowedUids: [principal.uid], allowedAppIds: [principal.appId]});
const code = expected => e => {assert.equal(e.code, expected, e.stack);return true;};
function cloudEnvironment(callback) {
  const old = {...process.env};
  for (const k of Object.keys(process.env)) if (k.endsWith("_EMULATOR_HOST") || ["FUNCTIONS_EMULATOR", "GOOGLE_APPLICATION_CREDENTIALS", "FIRESTORE_URL"].includes(k)) delete process.env[k];
  Object.assign(process.env, {GCLOUD_PROJECT: project, GOOGLE_CLOUD_PROJECT: project,
    FATOORA_SETTLEMENT_READ_TRANSPORT: targetModule.SETTLEMENT_STAGING_FLAG, FATOORA_SETTLEMENT_RUNTIME_ACCOUNT: targetModule.SETTLEMENT_READER_ACCOUNT});
  return Promise.resolve().then(callback).finally(() => {for (const k of Object.keys(process.env)) if (!(k in old)) delete process.env[k];Object.assign(process.env, old);});
}
const databases = [];
function database(options = {}) {const db = new Firestore({projectId: project, host: "firestore.googleapis.com:443", ssl: true, ...options});databases.push(db);return db;}
after(async () => {await Promise.all(databases.map(db => db.terminate()));});

test("pinned staging read capability accepts only a genuine read-only SDK transaction; no RPC", () => cloudEnvironment(async () => {
  const db = database(), target = targetModule.createStagingSettlementReadTarget(db);
  targetModule.assertApprovedSettlementReadTarget(db, target, "default_company");
  targetModule.assertSettlementReadTransaction(new Transaction(db, "synthetic", {readOnly: true}), db, target);
  assert.throws(() => targetModule.assertSettlementReadTransaction(new Transaction(db, "synthetic"), db, target), code("failed-precondition"));
  assert.throws(() => targetModule.assertSettlementReadTransaction({_firestore: db, _maxAttempts: 1}, db, target), code("failed-precondition"));
  assert.throws(() => targetModule.assertApprovedSettlementReadTarget(db, {kind: "staging_read_only"}), code("failed-precondition"));
  assert.throws(() => targetModule.assertApprovedSettlementReadTarget(db, target, "other-company"), code("failed-precondition"));
  assert.throws(() => targetModule.assertApprovedSettlementReadTarget(database(), target), code("failed-precondition"));
  // The capability is not a persistence option. Cloud posting still fails before any RPC.
  await assert.rejects(persistSettlementJournalTransaction(db, principal.uid, {}, undefined, {enableEmulatorPersistence: true, readTarget: target}), code("failed-precondition"));
  await assert.rejects(prepareSettlementJournalPersistence(new Transaction(db, "synthetic"), db, principal.uid, {}, undefined,
    {enableEmulatorPersistence: true, readTarget: target}), code("failed-precondition"));
}));
for (const [name, change] of [
  ["wrong project", () => database({projectId: "demo-other"})],
  ["other database", () => database({databaseId: "other"})],
  ["alternate host", () => database({host: "localhost:443"})],
  ["insecure TLS", () => database({ssl: false})],
  ["emulator override", () => {process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8192";return database();}],
  ["wrong runtime account", () => {process.env.FATOORA_SETTLEMENT_RUNTIME_ACCOUNT = "writer";return database();}],
  ["wrong flag", () => {delete process.env.FATOORA_SETTLEMENT_READ_TRANSPORT;return database();}],
  ["wrong runtime project", () => {process.env.GCLOUD_PROJECT = "demo-other";return database();}],
]) test(`staging capability rejects ${name} before RPC`, () => cloudEnvironment(() => assert.throws(() => targetModule.createStagingSettlementReadTarget(change()), code("failed-precondition"))));

test("valid control is bounded, exact-company, expiring and principal/app bound", () => assert.equal(validate(control(), principal, now), "a".repeat(64)));
for (const [name, patch] of [
  ["missing", () => undefined], ["disabled", c => ({...c, enabled: false})], ["expired", c => ({...c, expiresAtMillis: now})],
  ["unbounded activation", c => ({...c, expiresAtMillis: now + 86400001})], ["wrong company", c => ({...c, companyId: "other"})],
  ["unknown user", c => ({...c, allowedUids: ["other"]})], ["too many admins", c => ({...c, allowedUids: ["a", "b", "c", "d"]})],
  ["duplicate admins", c => ({...c, allowedUids: [principal.uid, principal.uid]})],
  ["other app", c => ({...c, allowedAppIds: ["other"]})], ["empty app list", c => ({...c, allowedAppIds: []})],
  ["extra field", c => ({...c, financialTotal: 0})], ["invalid revision", c => ({...c, revision: "1"})],
]) test(`pilot rejects ${name}`, () => assert.throws(() => validate(patch(control()), principal, now), code("permission-denied")));
test("fresh control reads detect edit even when the visible revision is reused", () => cloudEnvironment(async () => {
  const db = database(), target = targetModule.createStagingSettlementReadTarget(db);let value = control(), version = 1, reads = 0;
  db.doc = path => {assert.equal(path, "internal_read_controls/settlement_breakdown");return {get: async () => {reads++;return {data: () => value, updateTime: {seconds: version, nanoseconds: 0}};}};};
  const access = createSettlementPilotAccess(db, target, () => now), first = await access(principal);version++;
  assert.notEqual(await access(principal), first);value.enabled = false;
  await assert.rejects(access(principal), code("permission-denied"));assert.equal(reads, 3);
}));
for (const failure of [false, true]) test(`runtime canary is bounded, security-only and ${failure ? "retains failure" : "requires all four read grants"}`, () => cloudEnvironment(async () => {
  const db=database(), target=targetModule.createStagingSettlementReadTarget(db);let gets=0, queries=0, authReads=0;
  const snapshot={exists:true,ref:{path:"internal_read_controls/settlement_breakdown"},data:()=>({allowedUids:[principal.uid]})};
  db.doc=path=>{assert.equal(path,snapshot.ref.path);return {path,get:async()=>{gets++;return snapshot;}};};
  db.collection=path=>{assert.equal(path,"internal_read_controls");const query={where:(_f,op,id)=>{assert.equal(op,"==");assert.equal(id,"settlement_breakdown");return query;},select:f=>{assert.equal(f,"schemaVersion");return query;},limit:n=>{assert.equal(n,1);return query;},get:async()=>{queries++;return {size:1,docs:[snapshot]};}};return query;};
  db.runTransaction=async(fn,options)=>{assert.deepEqual(options,{readOnly:true});const tx=new Transaction(db,"synthetic",options);tx.get=async()=>{gets++;return snapshot;};return fn(tx);};
  const auth={getUser:async uid=>{authReads++;if(failure)throw Error("Synthetic Auth denial");return {uid};}};
  for(let i=0;i<2;i++) {
    const attempt=verifySettlementReadRuntime(db,auth,target);
    if(failure)await assert.rejects(attempt,/Synthetic Auth denial/);else await attempt;
  }
  assert.equal(gets,2);assert.equal(queries,1);assert.equal(authReads,1);
}));
