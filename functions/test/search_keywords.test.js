const assert = require("node:assert/strict");
const {test} = require("node:test");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
const {normalizeSearchText, buildSearchKeywords, documentSearchFields,
  searchKeywordLimit} = require("../shared/search_keywords");
const {searchUpdates} = require("../scripts/backfill_search_keywords");
const {buildSearchKeywords: invoiceMaintenanceKeywords} = require("../scripts/invoice_list_fields_common");

const cases = JSON.parse(readFileSync(join(__dirname, "../../test/fixtures/phase2_search_cases.json"), "utf8"));
for (const record of cases) {
  test(`normalized phrase prefixes: ${record.value}`, () => {
    assert.equal(normalizeSearchText(record.value), record.normalized);
    const keywords = buildSearchKeywords([record.value]);
    for (const query of record.matches) assert.ok(keywords.includes(normalizeSearchText(query)), query);
    for (const query of record.misses) assert.ok(!keywords.includes(normalizeSearchText(query)), query);
    assert.deepEqual(keywords, [...new Set(keywords)].sort());
    assert.deepEqual(invoiceMaintenanceKeywords([record.value]), keywords);
  });
}

test("search backfill changes metadata only, preserves stock/finance/ordering, and is idempotent", () => {
  const data = {invoiceNumber: "INV-2026-000123", customerSnapshot: {name: "أحمد   عبد الرحمن"},
    quantity: 5, currentStock: 100, grandTotal: 10, financialPosted: true,
    salesRepId: "rep", createdByUid: "rep", updatedAt: "unchanged"};
  const before = structuredClone(data);
  for (const collection of ["invoices", "items", "rep_inventory_balances"]) {
    const update = searchUpdates(collection, data);
    assert.ok(Object.keys(update).every((key) => ["searchKeywords", "hasStock"].includes(key)));
    assert.deepEqual(searchUpdates(collection, {...data, ...update}), {});
  }
  assert.deepEqual(data, before);
  assert.equal(documentSearchFields("rep_inventory_balances", {quantity: 0}).hasStock, false);
  assert.equal(documentSearchFields("rep_inventory_balances", {quantity: 1}).hasStock, true);
});

test("keyword budget bounds Firestore array index entries and prioritizes identifiers/names", () => {
  const values = ["INV-2026-00123", "Primary Customer",
    ...Array.from({length: 100}, (_, i) => `Long catalog item number ${i} with many words`)];
  const keywords = buildSearchKeywords(values);
  assert.ok(keywords.length <= searchKeywordLimit);
  assert.ok(keywords.includes("primary cust"));
  assert.deepEqual(buildSearchKeywords(values), keywords);
});
