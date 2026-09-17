const assert = require("node:assert/strict");
const path = require("node:path");
const {test} = require("node:test");

const {
  combineSalesTotals,
  dashboardDayRanges,
  isMissingDashboardIndexError,
  mapWithConcurrency,
} = require("../lib/trusted/dashboard_reporting");
const {Timestamp} = require("firebase-admin/firestore");
const {
  buildItemSearchKeywords,
  normalizeItemSearch,
} = require("../lib/trusted/inventory");

test("dashboard totals net confirmed returns from matching payment buckets", () => {
  const totals = combineSalesTotals(
    [
      {count: 3, amount: 120.125},
      {count: 2, amount: 80.5},
      {count: 1, amount: 30.25},
    ],
    [
      {count: 1, amount: 20.125},
      {count: 0, amount: 0},
      {count: 1, amount: 5.25},
    ],
  );

  assert.deepEqual(totals, {
    totalSales: 205.5,
    cashSales: 100,
    creditSales: 80.5,
    partialSales: 25,
    invoiceCount: 6,
  });
});

test("dashboard aggregation rejects missing payment buckets", () => {
  assert.throws(
    () => combineSalesTotals([{count: 1, amount: 10}], []),
    /cash, credit, and partial/,
  );
});

test("dashboard reports missing indexes as a deployment precondition", () => {
  assert.equal(isMissingDashboardIndexError({
    code: 9,
    details: "The query requires an index.",
  }), true);
  assert.equal(isMissingDashboardIndexError({
    code: 9,
    details: "Another failed precondition.",
  }), false);
  assert.equal(isMissingDashboardIndexError(new Error("requires an index")), false);
});

test("bounded mapper never exceeds the requested concurrency", async () => {
  let active = 0;
  let peak = 0;
  const values = Array.from({length: 13}, (_, index) => index);
  const result = await mapWithConcurrency(values, 4, async (value) => {
    active += 1;
    peak = Math.max(peak, active);
    await new Promise((resolve) => setTimeout(resolve, 2));
    active -= 1;
    return value * 2;
  });

  assert.equal(peak, 4);
  assert.deepEqual(result, values.map((value) => value * 2));
});

test("item search projection is normalized and deterministic", () => {
  assert.equal(normalizeItemSearch("  MODEL-X  "), "model-x");
  const first = buildItemSearchKeywords(["MODEL-X", "Coffee Beans"]);
  const second = buildItemSearchKeywords(["MODEL-X", "Coffee Beans"]);
  assert.deepEqual(first, second);
  assert.ok(first.includes("model"));
  assert.ok(first.includes("coffee"));
  assert.equal(new Set(first).size, first.length);
});

test("dashboard day buckets use Asia/Amman boundaries", () => {
  const through = Timestamp.fromDate(new Date("2026-09-16T18:00:00.000Z"));
  const ranges = dashboardDayRanges(through, through);
  assert.equal(ranges.length, 7);
  assert.equal(
    ranges[6].from.toDate().toISOString(),
    "2026-09-15T21:00:00.000Z",
  );
  assert.equal(
    ranges[6].to.toDate().toISOString(),
    "2026-09-16T20:59:59.999Z",
  );
});

test("index manifest covers every dashboard aggregate query", () => {
  const manifest = require(path.resolve(__dirname, "../../firestore.indexes.json"));
  const keys = new Set(manifest.indexes.map((index) => {
    const fields = index.fields.map((field) =>
      `${field.fieldPath}:${field.order || field.arrayConfig}`).join("|");
    return `${index.collectionGroup}|${fields}`;
  }));
  const expectIndex = (collection, fields) => {
    assert.ok(
      keys.has(`${collection}|${fields.join("|")}`),
      `Missing ${collection} dashboard index: ${fields.join(", ")}`,
    );
  };

  expectIndex("invoices", [
    "financialPosted:ASCENDING",
    "invoiceDate:ASCENDING",
    "grandTotal:ASCENDING",
  ]);
  expectIndex("invoices", [
    "salesRepId:ASCENDING",
    "financialPosted:ASCENDING",
    "invoiceDate:ASCENDING",
    "grandTotal:ASCENDING",
  ]);
  expectIndex("invoices", [
    "financialPosted:ASCENDING",
    "paymentType:ASCENDING",
    "invoiceDate:ASCENDING",
    "grandTotal:ASCENDING",
  ]);
  expectIndex("invoices", [
    "salesRepId:ASCENDING",
    "financialPosted:ASCENDING",
    "paymentType:ASCENDING",
    "invoiceDate:ASCENDING",
    "grandTotal:ASCENDING",
  ]);
  expectIndex("sales_returns", [
    "financialPosted:ASCENDING",
    "status:ASCENDING",
    "returnDate:ASCENDING",
    "grandTotal:ASCENDING",
  ]);
  expectIndex("sales_returns", [
    "salesRepId:ASCENDING",
    "financialPosted:ASCENDING",
    "status:ASCENDING",
    "returnDate:ASCENDING",
    "grandTotal:ASCENDING",
  ]);
  expectIndex("sales_returns", [
    "financialPosted:ASCENDING",
    "status:ASCENDING",
    "originalPaymentType:ASCENDING",
    "returnDate:ASCENDING",
    "grandTotal:ASCENDING",
  ]);
  expectIndex("sales_returns", [
    "salesRepId:ASCENDING",
    "financialPosted:ASCENDING",
    "status:ASCENDING",
    "originalPaymentType:ASCENDING",
    "returnDate:ASCENDING",
    "grandTotal:ASCENDING",
  ]);
  expectIndex("expenses", [
    "status:ASCENDING",
    "expenseDate:ASCENDING",
    "amount:ASCENDING",
  ]);
  expectIndex("expenses", [
    "paidByUid:ASCENDING",
    "status:ASCENDING",
    "expenseDate:ASCENDING",
    "amount:ASCENDING",
  ]);
  expectIndex("expenses", [
    "reimbursementStatus:ASCENDING",
    "amount:ASCENDING",
  ]);
  expectIndex("expenses", [
    "paidByUid:ASCENDING",
    "reimbursementStatus:ASCENDING",
    "amount:ASCENDING",
  ]);
  expectIndex("receipts", [
    "receiptDate:ASCENDING",
    "amount:ASCENDING",
  ]);
  expectIndex("receipts", [
    "salesRepId:ASCENDING",
    "receiptDate:ASCENDING",
    "amount:ASCENDING",
  ]);
  expectIndex("cash_balances", [
    "cashAccount:ASCENDING",
    "amount:ASCENDING",
  ]);
});
