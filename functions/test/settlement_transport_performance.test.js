"use strict";
const assert = require("node:assert/strict"), {test, after} = require("node:test");
const {writeFileSync, readFileSync, existsSync, mkdirSync} = require("node:fs");
if (process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8192") throw Error("Isolated synthetic emulator required.");
const {initializeApp, deleteApp} = require("firebase-admin/app"), {getFirestore} = require("firebase-admin/firestore");
const {volumeFixture} = require("./helpers/settlement_volume_fixture"), {profiledDatabase, measure} = require("./helpers/settlement_transport_profile");
const {verifySettlementBreakdownDetailPages} = require("../lib/trusted/settlement_breakdown_presentation");
const app = initializeApp({projectId: "demo-fatoora-phase2b7"}, "phase2b13-performance"), real = getFirestore(app), db = profiledDatabase(real);
const mode = process.env.SETTLEMENT_PROFILE_MODE ?? "optimized", baseline = mode === "baseline";
if (!["baseline", "optimized", "optimized-v1", "bounded-memory"].includes(mode)) throw Error("Unsupported local profiling mode.");
const {createSettlementTransport} = require(`../lib/trusted/settlement_transport${baseline ? "_phase2b12_baseline" : ""}`);
const records = [], fixtureFile = "../build/phase2b13-fixtures.json";
const ids = existsSync(fixtureFile) ? JSON.parse(readFileSync(fixtureFile)) : {};
after(async () => {writeFileSync(`../output/phase2b13/${mode}-performance.json`, JSON.stringify({synthetic: true, mode, authProvider: "injected", records}, null, 2));await deleteApp(app);});
for (const count of (process.env.SETTLEMENT_PROFILE_COUNTS ?? "3000,6000").split(",").map(Number)) {
  test(`${mode}: identical ${count}-movement fixture`, {timeout: 900000,
    skip: process.env.SETTLEMENT_PROFILE_MODE === undefined ? "Explicit synthetic performance opt-in required" : false}, async t => {
    if (!ids[count]) {
      const f = await volumeFixture(real, count, {mixed: true});
      ids[count] = {companyId: f.companyId, salesRepId: f.rep, settlementId: f.currentId, uid: f.admin, remainingUnits: f.remainingUnits};
      writeFileSync(fixtureFile, JSON.stringify(ids, null, 2));
    }
    const f = ids[count];
    for (let repeat = 0; repeat < Number(process.env.SETTLEMENT_PROFILE_REPEATS ?? 3); repeat++) {
      let authCalls = 0;
      const auth = {async getUser(uid) {authCalls++;return {uid, disabled: false};}}, svc = createSettlementTransport(db, auth);
      const who = {uid: f.uid, authTime: Math.floor(Date.now() / 1000)}, schemaVersion = baseline || process.env.SETTLEMENT_PROFILE_V1 === "1" ? 1 : 2;
      const requests = [], pages = [], batches = [], at = performance.now();
      let response;
      try {
        for (;;) {
          const request = response ? {schemaVersion, action: "page", token: response.nextToken} :
            {schemaVersion, action: "start", companyId: f.companyId, salesRepId: f.salesRepId, settlementId: f.settlementId};
          const measured = await measure(() => svc.request(who, request));requests.push(measured.metrics);
          const batch = measured.result.kind === "pages" ? measured.result.pages : [measured.result];
          assert.ok(batch.length);for (const envelope of batch) pages.push(envelope.page);batches.push(batch.map(e => e.page));
          response = batch.at(-1);if (!response.nextToken) break;
        }
        assert.equal(verifySettlementBreakdownDetailPages(pages).totals.remainingUnits, f.remainingUnits);
        const pdf = await measure(() => svc.request(who, {schemaVersion, action: "authorizePdf", token: response.exportToken}));
        const record = {count, repeat, schemaVersion, pages: pages.length, totalMillis: performance.now() - at, requests, pdf: pdf.metrics, authCalls, ...svc.statistics()};
        records.push(record);t.diagnostic(JSON.stringify({count, repeat, totalMillis: record.totalMillis, reads: requests.reduce((n,m) => n + m.documentReads, pdf.metrics.documentReads)}));
        if (!baseline && schemaVersion === 2 && repeat === 0) {
          mkdirSync("../build/phase2b13-captures", {recursive: true});
          writeFileSync(`../build/phase2b13-captures/${count}.json`, JSON.stringify({synthetic: true, ...f, batches}));
        }
        writeFileSync(`../output/phase2b13/${mode}-performance.json`, JSON.stringify({synthetic: true, mode, authProvider: "injected", records}, null, 2));
      } catch (e) {
        records.push({count, repeat, schemaVersion, error: e.code, millis: performance.now() - at, requests, ...svc.statistics()});
        if (baseline && count > 3000 && (e.code === "resource-exhausted" || e.code === "failed-precondition" && performance.now() - at >= 300000)) {
          t.diagnostic("Baseline admission/expiry prevented complete delivery; partial pages cannot certify totals.");break;
        }
        throw e;
      }
    }
  });
}
