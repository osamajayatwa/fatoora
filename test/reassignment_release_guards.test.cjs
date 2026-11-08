"use strict";
const {test} = require("node:test"), assert = require("node:assert/strict"), vm = require("node:vm");
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const root = path.resolve(__dirname, ".."), policy = require("../config/firebase/reassignment-release.review.json");
test("candidate policy rejects production, broad function deployment and release-hold removal before filesystem writes", () => {
  const source = fs.readFileSync(path.join(root, "scripts/reassignment-release-candidate.cjs"), "utf8");
  for (const edit of [p => p.projectId = "fatoora-6b192", p => p.deployAllowed = true,
    p => p.scope.functions.push("recordCashSettlement"), p => p.historicalWritesAllowed = true]) {
    const p = structuredClone(policy); edit(p); let writes = 0;
    const module = {exports: {}};
    const req = name => name === "node:fs" ? {readFileSync: () => JSON.stringify(p), writeFileSync: () => writes++} : require(name);
    vm.runInNewContext(source, {require: req, module, __dirname: path.join(root, "scripts"), process});
    assert.throws(() => module.exports.policy(), /scope\/hold changed/); assert.equal(writes, 0);
  }
});
test("candidate executor exposes no deployment action", () => {
  const result = cp.spawnSync(process.execPath, ["scripts/reassignment-release-candidate.cjs", "deploy"], {cwd: root, encoding: "utf8"});
  assert.equal(result.status, 1); assert.match(result.stderr, /Only offline prepare\/seal\/verify/);
});
test("index review is additive and exactly covers posted-history sorts and search without status equality", () => {
  const {expectedIndexes} = require("../scripts/reassignment-release-indexes.cjs");
  const baseline = JSON.parse(cp.execFileSync("git", ["show", "HEAD:firestore.indexes.json"], {cwd: root}));
  const current = JSON.parse(fs.readFileSync(path.join(root, "firestore.indexes.json")));
  const keys = new Set(current.indexes.map(i => JSON.stringify(i)));
  assert.equal(current.indexes.length, 300); assert.equal(keys.size, 300);
  for (const i of [...baseline.indexes, ...expectedIndexes()]) assert.ok(keys.has(JSON.stringify(i)));
  assert.deepEqual(current.fieldOverrides, baseline.fieldOverrides);
});
test("native staging evidence separates reusable owner indexes from held history dependencies", () => {
  const live = JSON.parse(fs.readFileSync(path.join(root, "build/reassignment-release-evidence/live-staging-read.json")));
  assert.equal(live.project, policy.projectId); assert.equal(live.documentWrites, 0); assert.equal(live.queryPlansAnalyze, false);
  assert.equal(live.queryPlans.filter(p => p.status === "PASS").length, 42);
  const missing = live.queryPlans.filter(p => p.status !== "PASS"); assert.equal(missing.length, 42);
  assert.ok(missing.every(p => p.missingIndex && p.scope.startsWith("customer-history")));
});
