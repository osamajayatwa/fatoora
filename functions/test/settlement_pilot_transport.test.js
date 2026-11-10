"use strict";
const {test, after} = require("node:test"), assert = require("node:assert/strict");
if (process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8192") throw Error("Isolated synthetic emulator required");
const {initializeApp, deleteApp} = require("firebase-admin/app"), {getFirestore} = require("firebase-admin/firestore");
const {createSettlementTransport} = require("../lib/trusted/settlement_transport");
const {validateSettlementPilotControl, SETTLEMENT_STAGING_APPS} = require("../lib/trusted/settlement_staging_access");
const {volumeFixture} = require("./helpers/settlement_volume_fixture");
const app = initializeApp({projectId: "demo-fatoora-phase2b7"}, "phase2b15-pilot-security"), db = getFirestore(app);
after(() => deleteApp(app));
const denied = code => e => {assert.equal(e.code, code, e.stack);return true;};
async function fixture() {
  const f = await volumeFixture(db, 400, {mixed: true}), who = {uid: f.admin, authTime: Math.floor(Date.now() / 1000), appId: SETTLEMENT_STAGING_APPS[0]};
  let c = {schemaVersion: 1, enabled: true, companyId: "default_company", revision: "a".repeat(64),
    expiresAtMillis: Date.now() + 3600000, allowedUids: [f.admin], allowedAppIds: [who.appId]};
  let checks = 0, hook = () => {};
  const svc = createSettlementTransport(db, {getUser: async uid => ({uid, disabled: false})}, Date.now,
    {access: async p => {hook(++checks);return validateSettlementPilotControl(c, p, Date.now());}});
  return {svc, who, control: c, setHook: h => {checks = 0;hook = h;},
    start: {schemaVersion: 2, action: "start", companyId: f.companyId, salesRepId: f.rep, settlementId: f.currentId}};
}
for (const change of ["disabled", "allowlist", "expired", "revision"]) test(`fresh ${change} control rejects cached pages and destroys retained session`, async () => {
  const f = await fixture(), first = await f.svc.request(f.who, f.start), token = first.pages.at(-1).nextToken;
  if (change === "disabled") f.control.enabled = false;
  if (change === "allowlist") f.control.allowedUids = ["other"];
  if (change === "expired") f.control.expiresAtMillis = Date.now() - 1;
  if (change === "revision") f.control.revision = "b".repeat(64);
  await assert.rejects(f.svc.request(f.who, {schemaVersion: 2, action: "page", token}), denied(change === "revision" ? "failed-precondition" : "permission-denied"));
  assert.equal(f.svc.statistics().sessions, 0);
});
test("kill switch after full initial verification releases no sensitive result", async () => {
  const f = await fixture();f.setHook(count => {if (count === 2) f.control.enabled = false;});
  await assert.rejects(f.svc.request(f.who, f.start), denied("permission-denied"));assert.equal(f.svc.statistics().sessions, 0);
});
test("changed control before page delivery and PDF permission fails closed", async () => {
  for (const pdf of [false, true]) {
    const f = await fixture();let r = await f.svc.request(f.who, f.start);
    if (pdf) while (r.pages.at(-1).nextToken) r = await f.svc.request(f.who, {schemaVersion: 2, action: "page", token: r.pages.at(-1).nextToken});
    f.setHook(count => {if (count === 2) f.control.revision = "b".repeat(64);});
    await assert.rejects(f.svc.request(f.who, {schemaVersion: 2, action: pdf ? "authorizePdf" : "page",
      token: pdf ? r.pages.at(-1).exportToken : r.pages.at(-1).nextToken}), denied("failed-precondition"));
    assert.equal(f.svc.statistics().sessions, 0);
  }
});
test("App identity cannot be mixed inside a valid signed session", async () => {
  const f = await fixture(), r = await f.svc.request(f.who, f.start);f.control.allowedAppIds = [...SETTLEMENT_STAGING_APPS];
  await assert.rejects(f.svc.request({...f.who, appId: SETTLEMENT_STAGING_APPS[1]}, {schemaVersion: 2, action: "page", token: r.pages.at(-1).nextToken}), denied("failed-precondition"));
});
test("callable rejects an oversized raw body before authentication or financial reads", async () => {
  const response = await fetch("http://127.0.0.1:5005/demo-fatoora-phase2b7/us-central1/getSettlementBreakdown", {
    method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({data: {padding: "x".repeat(20000)}}),
  });
  assert.equal(response.status, 429);assert.equal((await response.json()).error.status, "RESOURCE_EXHAUSTED");
});
