const assert = require("node:assert/strict");
const {before, after, test} = require("node:test");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {confirmInvoiceTransaction} = require("../lib/trusted/confirm_invoice");
const {confirmSalesReturnTransaction} = require("../lib/trusted/confirm_sales_return");
const {createReceiptTransaction} = require("../lib/trusted/create_receipt");

const app = initializeApp({projectId: "fatoora-phase1-test"}, "phase1-tests");
const db = getFirestore(app);
const date = Timestamp.fromDate(new Date("2026-10-19T09:00:00Z"));
before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Phase 1 tests require the emulator.");
});
after(() => deleteApp(app));

function line(id, overrides = {}) {
  return {lineId: id, lineType: "custom", itemId: null, itemName: "Service",
    description: "At site", unit: "service", quantity: 1, unitPrice: 10,
    discount: 0, taxPercent: 0, ...overrides};
}
async function fixture(suffix, role = "sales_rep") {
  const companyId = `phase1-${suffix}`;
  const uid = `${companyId}-${role}`;
  const path = (collection, id) => db.doc(`companies/${companyId}/${collection}/${id}`);
  await db.doc(`users/${uid}`).set({uid, companyId, name: uid, role,
    active: true, approvalStatus: "approved"});
  await path("customers", "customer").set({id: "customer", companyId, name: "Customer",
    active: true, createdByUid: uid, currentBalance: 0, totalSales: 0, totalPaid: 0});
  await path("settings", "app").set({permissionSettings: {
    allowSalesRepDiscount: false, allowSalesRepPriceEdit: false,
    allowSalesRepCreateReceipts: false, allowSalesRepCreateReturns: false,
    allowSalesRepCreateQuotations: false,
  }});
  async function draft(id, items, overrides = {}) {
    await path("invoices", id).set({id, companyId, invoiceNumber: `INV-${id}`,
      invoiceDate: date, dueDate: date, invoiceStatus: "draft", isLocked: false,
      createdByUid: uid, createdByName: uid, createdByRole: role,
      salesRepId: uid, salesRepName: uid, customerId: "customer",
      customerSnapshot: {id: "customer", name: "Customer"},
      stockSourceType: role === "sales_rep" ? "salesRep" : "companyWarehouse",
      stockSourceSalesRepId: role === "sales_rep" ? uid : "",
      financialPosted: false, inventoryPosted: false,
      hasReceivedPayment: false, paidAmount: 0,
      grandTotal: 999999, subtotal: 999999, totalDiscount: 0,
      items, ...overrides});
  }
  return {companyId, uid, path, draft};
}
async function effects(f) {
  const names = ["rep_inventory_movements", "stock_movements", "customer_transactions",
    "cash_movements", "financial_ledger_entries"];
  return Object.fromEntries(await Promise.all(names.map(async (name) => [name,
    (await db.collection(`companies/${f.companyId}/${name}`).get()).size])));
}

// Match the existing trusted transaction suite's narrowly scoped workaround
// for the emulator's intermittent transaction-closed contention response.
async function retryTransientTransaction(operation) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      return await operation();
    } catch (error) {
      if (!String(error?.message ?? error).includes("Transaction is invalid or closed") || attempt === 2) {
        throw error;
      }
    }
  }
}

for (const role of ["sales_rep", "admin"]) {
  test(`${role}: custom-only, catalog-only and mixed invoices accept chosen prices and discounts`, async () => {
    const f = await fixture(`valid-${role}`, role);
    const itemId = `${f.companyId}-item`;
    await db.doc(`items/${itemId}`).set({id: itemId, name: "Catalog", code: "C",
      unit: "pcs", price: 999, active: true, deleted: false, trackStock: false});
    const catalog = (id, overrides) => line(id,
      {lineType: "catalog", itemId, ...overrides});
    const cases = [
      [line("custom", {quantity: 2, discount: 19.999})],
      [catalog("catalog", {unitPrice: 5, discount: 1})],
      [catalog("free", {unitPrice: 0}), line("paid", {discount: 9})],
    ];
    for (let i = 0; i < cases.length; i++) {
      const id = `valid-${i}`;
      await f.draft(id, cases[i]);
      await confirmInvoiceTransaction(db, f.uid, f.companyId, id);
      const invoice = (await f.path("invoices", id).get()).data();
      assert.equal(invoice.grandTotal, [0.001, 4, 1][i]);
      assert.equal(invoice.isLocked, true);
      assert.equal(invoice.items[0].unitPrice, cases[i][0].unitPrice);
      assert.equal(invoice.items[0].discount, cases[i][0].discount);
    }
    assert.deepEqual(await effects(f), {rep_inventory_movements: 0, stock_movements: 0,
      customer_transactions: 3, cash_movements: 0, financial_ledger_entries: 3});
  });

  test(`${role}: invalid quantities, prices, totals and empty invoices reject atomically`, async () => {
    const f = await fixture(`invalid-${role}`, role);
    const cases = [[], [line("zero", {unitPrice: 0})], [line("qty", {quantity: 0})],
      [line("qty", {quantity: -1})], [line("tiny", {quantity: 0.0001})],
      [line("price", {unitPrice: -0.001})], [line("discount", {discount: 10})],
      [line("excess", {discount: 11})]];
    for (let i = 0; i < cases.length; i++) {
      const id = `invalid-${i}`;
      await f.draft(id, cases[i]);
      await assert.rejects(confirmInvoiceTransaction(db, f.uid, f.companyId, id),
        (error) => error.code === "invalid-argument");
      assert.equal((await f.path("invoices", id).get()).data().invoiceStatus, "draft");
    }
    assert.deepEqual(await effects(f), {rep_inventory_movements: 0, stock_movements: 0,
      customer_transactions: 0, cash_movements: 0, financial_ledger_entries: 0});
  });
}

test("rep custody uses cumulative quantities, fails safely and posts once under concurrency", async () => {
  const f = await fixture("custody");
  const itemId = "phase1-custody-item";
  await db.doc(`items/${itemId}`).set({id: itemId, name: "Tracked", unit: "pcs",
    price: 999, active: true, deleted: false, trackStock: true, currentStock: 100});
  const balance = f.path("rep_inventory_balances", `${f.uid}_${itemId}`);
  await balance.set({id: balance.id, companyId: f.companyId, salesRepId: f.uid,
    itemId, quantity: 3, createdAt: date});
  const catalog = (id, quantity) => line(id, {lineType: "catalog", itemId, quantity});
  await f.draft("too-much", [catalog("one", 2), catalog("two", 2)]);
  await assert.rejects(confirmInvoiceTransaction(db, f.uid, f.companyId, "too-much"),
    (error) => error.code === "failed-precondition");
  assert.equal((await balance.get()).data().quantity, 3);
  assert.equal((await f.path("customers", "customer").get()).data().currentBalance, 0);
  assert.equal((await effects(f)).rep_inventory_movements, 0);
  await f.draft("exact", [catalog("one", 1), catalog("two", 2)],
    {hasReceivedPayment: true, paidAmount: 5});
  const attempts = await Promise.all([
    retryTransientTransaction(() => confirmInvoiceTransaction(db, f.uid, f.companyId, "exact")),
    retryTransientTransaction(() => confirmInvoiceTransaction(db, f.uid, f.companyId, "exact")),
  ]);
  assert.equal(attempts.filter((result) => result.alreadyPosted).length, 1);
  assert.equal((await balance.get()).data().quantity, 0);
  assert.equal((await db.doc(`items/${itemId}`).get()).data().currentStock, 100);
  assert.equal((await f.path("cash_balances", `rep_${f.uid}`).get()).data().amount, 5);
  assert.equal((await f.path("customers", "customer").get()).data().currentBalance, 25);
  assert.deepEqual(await effects(f), {rep_inventory_movements: 2, stock_movements: 0,
    customer_transactions: 2, cash_movements: 1, financial_ledger_entries: 2});
});

test("rep cannot confirm warehouse-source, missing-source or another rep's source, even for custom-only drafts", async () => {
  const f = await fixture("sources");
  for (const [id, source] of [
    ["warehouse", {stockSourceType: "companyWarehouse", stockSourceSalesRepId: ""}],
    ["legacy", {stockSourceType: "", stockSourceSalesRepId: ""}],
    ["other-rep", {stockSourceType: "salesRep", stockSourceSalesRepId: "another-rep"}],
  ]) {
    await f.draft(id, [line("custom")], {createdByUid: "admin", createdByRole: "admin", ...source});
    await assert.rejects(confirmInvoiceTransaction(db, f.uid, f.companyId, id),
      (error) => error.code === "permission-denied");
    assert.equal((await f.path("invoices", id).get()).data().invoiceStatus, "draft");
  }
  assert.equal((await effects(f)).financial_ledger_entries, 0);
});

test("admin warehouse confirmation preserves stock source and rejects cumulative shortages", async () => {
  const f = await fixture("admin-stock", "admin");
  const itemId = "phase1-admin-stock-item";
  const itemRef = db.doc(`items/${itemId}`);
  await itemRef.set({id: itemId, name: "Tracked", unit: "pcs", price: 10,
    active: true, deleted: false, trackStock: true, currentStock: 3});
  const catalog = (id, quantity) => line(id, {lineType: "catalog", itemId, quantity});
  await f.draft("too-much", [catalog("one", 2), catalog("two", 2)]);
  await assert.rejects(confirmInvoiceTransaction(db, f.uid, f.companyId, "too-much"),
    (error) => error.code === "failed-precondition");
  assert.equal((await itemRef.get()).data().currentStock, 3);
  assert.equal((await effects(f)).stock_movements, 0);
  await f.draft("exact", [catalog("one", 1), catalog("two", 2)]);
  await confirmInvoiceTransaction(db, f.uid, f.companyId, "exact");
  assert.equal((await itemRef.get()).data().currentStock, 0);
  assert.equal((await effects(f)).stock_movements, 2);
  assert.equal((await effects(f)).rep_inventory_movements, 0);
});

test("backend denies cross-rep documents and customers even when creator or assignment is forged", async () => {
  const f = await fixture("ownership");
  await f.draft("other-document", [line("custom")], {salesRepId: "another-rep"});
  await assert.rejects(confirmInvoiceTransaction(db, f.uid, f.companyId, "other-document"),
    (error) => error.code === "permission-denied");
  await f.path("customers", "customer").update({createdByUid: "another-rep"});
  await f.draft("other-customer", [line("custom")]);
  await assert.rejects(confirmInvoiceTransaction(db, f.uid, f.companyId, "other-customer"),
    (error) => error.code === "permission-denied");
  await assert.rejects(createReceiptTransaction(db, f.uid, f.companyId, "ownership-receipt",
    {customerId: "customer", amount: 1, receiptDate: date}),
  (error) => error.code === "permission-denied");
});

test("rep receipts and returns ignore obsolete toggles and retain financial limits and idempotency", async () => {
  const f = await fixture("receipt-return");
  await f.draft("sale", [line("service", {quantity: 2})]);
  await confirmInvoiceTransaction(db, f.uid, f.companyId, "sale");
  const receipt = {customerId: "customer", amount: 5, receiptDate: date, paymentMethod: "cash"};
  await createReceiptTransaction(db, f.uid, f.companyId, "phase1-receipt-key", receipt);
  await createReceiptTransaction(db, f.uid, f.companyId, "phase1-receipt-key", receipt);
  await assert.rejects(createReceiptTransaction(db, f.uid, f.companyId, "phase1-overpay-key",
    {...receipt, amount: 21}), (error) => error.code === "failed-precondition");
  const input = {originalInvoiceId: "sale", reason: "Service credit", returnDate: date,
    refundType: "credit_customer_balance",
    items: [{originalInvoiceItemId: "sale:line:service", returnedQuantity: 1}]};
  await confirmSalesReturnTransaction(db, f.uid, f.companyId, "return", input);
  const replay = await confirmSalesReturnTransaction(db, f.uid, f.companyId, "return", input);
  assert.equal(replay.alreadyPosted, true);
  assert.equal((await f.path("customers", "customer").get()).data().currentBalance, 5);
  assert.equal((await effects(f)).rep_inventory_movements, 0);
  assert.equal((await effects(f)).stock_movements, 0);
  assert.equal((await db.collection(`companies/${f.companyId}/receipts`).get()).size, 1);
  assert.equal((await db.collection(`companies/${f.companyId}/sales_returns`).get()).size, 1);
  await assert.rejects(confirmSalesReturnTransaction(db, f.uid, f.companyId, "excess-return",
    {...input, items: [{originalInvoiceItemId: "sale:line:service", returnedQuantity: 2}]}),
  (error) => error.code === "failed-precondition");
  await f.path("sales_returns", "partial-posting").set({companyId: f.companyId,
    salesRepId: f.uid, createdByUid: f.uid, status: "draft", financialPosted: true});
  await assert.rejects(confirmSalesReturnTransaction(db, f.uid, f.companyId, "partial-posting", input),
    (error) => error.code === "failed-precondition");
  await f.path("sales_returns", "other-rep-return").set({companyId: f.companyId,
    salesRepId: "another-rep", createdByUid: f.uid, status: "draft"});
  await assert.rejects(confirmSalesReturnTransaction(db, f.uid, f.companyId, "other-rep-return", input),
    (error) => error.code === "permission-denied");
  await f.path("customers", "customer").update({createdByUid: "another-rep"});
  await assert.rejects(confirmSalesReturnTransaction(db, f.uid, f.companyId, "other-customer-return", input),
    (error) => error.code === "permission-denied");
});
