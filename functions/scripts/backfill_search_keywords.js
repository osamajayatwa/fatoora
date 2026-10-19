"use strict";

const {parseOptions, initializeFirestore, scanCollection} = require("./invoice_list_fields_common");
const {documentSearchFields} = require("../shared/search_keywords");

function searchUpdates(collection, data) {
  const expected = documentSearchFields(collection, data);
  return Object.fromEntries(Object.entries(expected).filter(([key, value]) =>
    JSON.stringify(data[key]) !== JSON.stringify(value)));
}

async function* changes(db, options) {
  for (const collection of ["invoices", "items", "rep_inventory_balances"]) {
    if (collection === "items" && options.companyId !== "default_company") continue;
    const ref = collection === "items" ? db.collection("items") :
      db.collection(`companies/${options.companyId}/${collection}`);
    for await (const document of scanCollection(ref, Math.min(options.pageSize, 500))) {
      const data = document.data();
      if (data.companyId && data.companyId !== options.companyId) continue;
      const updates = searchUpdates(collection, data);
      if (Object.keys(updates).length) yield {document, updates, collection};
    }
  }
}

async function main() {
  const options = parseOptions(process.argv.slice(2));
  const db = initializeFirestore(options.projectId);
  const counts = {};
  let plannedWrites = 0;
  for await (const change of changes(db, options)) {
    counts[change.collection] = (counts[change.collection] ?? 0) + 1;
    plannedWrites++;
  }
  console.log(JSON.stringify({project: options.projectId, company: options.companyId,
    mode: options.apply ? "apply" : "dry-run", plannedWrites, counts}, null, 2));
  if (!options.apply) return;
  if (plannedWrites > options.maxWrites) throw new Error("Review dry-run and increase --max-writes before applying.");
  let applied = 0;
  // A precondition prevents overwriting newer search metadata if a posting or
  // edit races this maintenance pass. Only searchKeywords/hasStock are written.
  for await (const {document, updates} of changes(db, options)) {
    if (applied >= options.maxWrites) throw new Error("Write limit reached; rerun dry-run.");
    await document.ref.update(updates, {lastUpdateTime: document.updateTime});
    applied++;
  }
  console.log(JSON.stringify({applied}));
}

if (require.main === module) main().catch((error) => {
  console.error(`[search-keywords] ${error.message}`);
  process.exitCode = 1;
});
module.exports = {searchUpdates};
