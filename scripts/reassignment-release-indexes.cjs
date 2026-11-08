"use strict";
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const root = path.resolve(__dirname, "..");
const SORTS = ["invoiceNumberLower", "invoiceDate", "customerNameLower", "salesRepName", "grandTotal", "remainingAmount", "invoiceStatus", "createdAt"];
const key = value => JSON.stringify(value);
function expectedIndexes() {
  return SORTS.flatMap(sort => ["ASCENDING", "DESCENDING"].flatMap(order => [false, true].map(search => ({
    collectionGroup: "invoices", queryScope: "COLLECTION", fields: [
      ...(search ? [{fieldPath: "searchKeywords", arrayConfig: "CONTAINS"}] : []),
      ...["customerId", "financialPosted"].filter(f => f !== sort).map(fieldPath => ({fieldPath, order: "ASCENDING"})),
      {fieldPath: sort, order},
    ],
  }))));
}
function review(write = false) {
  const baseline = JSON.parse(cp.execFileSync("git", ["show", "HEAD:firestore.indexes.json"], {cwd: root}));
  const current = JSON.parse(fs.readFileSync(path.join(root, "firestore.indexes.json")));
  const oldKeys = new Set(baseline.indexes.map(key)), additions = current.indexes.filter(i => !oldKeys.has(key(i)));
  if (current.indexes.filter(i => oldKeys.has(key(i))).length !== baseline.indexes.length ||
      key(current.fieldOverrides) !== key(baseline.fieldOverrides)) throw Error("Unrelated baseline index change");
  if (![32, 64].includes(additions.length) || additions.some(i => i.collectionGroup !== "invoices" || i.queryScope !== "COLLECTION")) {
    throw Error("Unexpected release index scope");
  }
  const final = expectedIndexes();
  const report = {baseline: baseline.indexes.length, initiallyAdded: 64, finalAdditions: final.length,
    removedExisting: 0, newTotal: baseline.indexes.length + final.length,
    reason: "Existing owner branch uses native-verified index merging; posted branch filters financialPosted without lifecycle status.",
    source: "https://firebase.google.com/docs/firestore/query-data/index-overview#use_index_merging",
    originalReview: additions.map(index => ({index, decision: index.fields.some(f => f.fieldPath === "salesRepId")
      ? "OMIT_OWNER_BRANCH_NATIVE_PLANS_PASS" : final.some(i => key(i) === key(index)) ? "RETAIN" : "REPLACE_REMOVE_STATUS_EQUALITY"})),
    finalIndexes: final};
  if (write) {
    const source = cp.execFileSync("git", ["show", "HEAD:firestore.indexes.json"], {cwd: root}).toString();
    const render = final.map(i => `    {\n      "collectionGroup": "invoices",\n      "queryScope": "COLLECTION",\n      "fields": [\n${i.fields.map(f => "        " + key(f).replaceAll(":", ": ").replaceAll(",", ", ")).join(",\n")}\n      ]\n    }`).join(",\n");
    fs.writeFileSync(path.join(root, "firestore.indexes.json"), source.replace(/\r?\n  \],\r?\n  "fieldOverrides"/, `,\n${render}\n  ],\n  "fieldOverrides"`));
    const directory = path.join(root, "build/reassignment-release-evidence"); fs.mkdirSync(directory, {recursive: true});
    fs.writeFileSync(path.join(directory, "index-review.json"), JSON.stringify(report, null, 2) + "\n");
  }
  return report;
}
if (require.main === module) {
  if (process.argv.length !== 3 || !["--review", "--write"].includes(process.argv[2])) throw Error("Use --review or --write; no deployment mode");
  const result = review(process.argv[2] === "--write");
  console.log(JSON.stringify({baseline: result.baseline, additions: result.finalAdditions, total: result.newTotal, removedExisting: 0}));
}
module.exports = {expectedIndexes, review};
