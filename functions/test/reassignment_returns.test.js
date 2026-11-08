"use strict";
const assert = require("node:assert/strict");
const {before, after, test} = require("node:test");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {confirmInvoiceTransaction} = require("../lib/trusted/confirm_invoice");
const {reassignCustomerTransaction} = require("../lib/trusted/customer_assignment");
const {createReceiptTransaction} = require("../lib/trusted/create_receipt");
const {confirmSalesReturnTransaction} = require("../lib/trusted/confirm_sales_return");
const {getDashboardSnapshot} = require("../lib/trusted/dashboard_reporting");
const {getFinancialLedgerSummary, reconcileFinancialLedgerProjection} = require("../lib/trusted/financial_ledger_reporting");
const app = initializeApp({projectId: "demo-fatoora-reassignment-returns"});
const db = getFirestore(app);
const saleDate = Timestamp.fromDate(new Date("2026-11-01T09:00:00Z"));
const returnDate = Timestamp.fromDate(new Date("2026-11-03T09:00:00Z"));
let sequence = 0;
before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || "", /^127\.0\.0\.1:\d+$/);
  const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${app.options.projectId}/databases/(default)/documents`, {method: "DELETE"});
  assert.ok(response.ok);
});
after(() => deleteApp(app));
async function fixture({adminSale = false, paid = 0} = {}) {
  const companyId = `workflow-${++sequence}`, admin = `${companyId}-admin`, a = `${companyId}-a`, b = `${companyId}-b`;
  const seller = adminSale ? admin : a, item = `${companyId}-item`;
  const ref = (collection, id) => db.doc(`companies/${companyId}/${collection}/${id}`);
  const rows = async (collection) => (await db.collection(`companies/${companyId}/${collection}`).get()).docs.map((d) => d.data());
  const batch = db.batch();
  for (const [uid, role] of [[admin, "admin"], [a, "sales_rep"], [b, "sales_rep"]]) {
    batch.set(db.doc(`users/${uid}`), {uid, role, companyId, name: uid, active: true, approvalStatus: "approved"});
  }
  batch.set(ref("customers", "customer"), {id: "customer", companyId, name: "Synthetic", active: true,
    createdByUid: seller, assignedToUid: seller, assignmentVersion: 1, assignmentRevision: 0,
    currentBalance: 0, totalSales: 0, totalPaid: 0});
  batch.set(db.doc(`items/${item}`), {id: item, companyId, name: "Synthetic item", code: item, unit: "pcs",
    active: true, deleted: false, trackStock: true, currentStock: 20, costPrice: 2});
  batch.set(ref("rep_inventory_balances", `${a}_${item}`), {id: `${a}_${item}`, companyId, salesRepId: a, itemId: item, quantity: 10});
  await batch.commit();
  const draft = async (id, uid, initialPaid = 0, date = saleDate) => ref("invoices", id).set({id, companyId,
    invoiceNumber: `INV-${id}`, invoiceDate: date, dueDate: date,
    customerId: "customer", customerSnapshot: {id: "customer", name: "Synthetic"},
    createdByUid: uid, createdByName: uid, createdByRole: uid === admin ? "admin" : "sales_rep",
    salesRepId: uid, salesRepName: uid, invoiceStatus: "draft", isLocked: false,
    financialPosted: false, inventoryPosted: false, paidAmount: initialPaid, hasReceivedPayment: initialPaid > 0,
    stockSourceType: uid === admin ? "companyWarehouse" : "salesRep", stockSourceSalesRepId: uid === admin ? "" : uid,
    items: [{lineId: "line", lineType: "catalog", itemId: item, itemName: "Synthetic item", unit: "pcs",
      quantity: 3, unitPrice: 10, discount: 0, taxPercent: 0}]});
  await draft("old", seller, paid);
  await confirmInvoiceTransaction(db, seller, companyId, "old");
  const transfer = async (target = b) => {
    const c = (await ref("customers", "customer").get()).data();
    await reassignCustomerTransaction(db, admin, {companyId, customerId: "customer", assignedToUid: target,
      expectedAssignedToUid: c.assignedToUid, expectedAssignmentRevision: c.assignmentRevision,
      reason: "Synthetic transfer", idempotencyKey: `transfer-${c.assignmentRevision}`});
  };
  const returned = (id, quantity, refundType = "credit_customer_balance", actor = admin) =>
    confirmSalesReturnTransaction(db, actor, companyId, id, {originalInvoiceId: "old", returnDate,
      reason: "Synthetic return", refundType, items: [{originalInvoiceItemId: "old:line:line", returnedQuantity: quantity}],
      salesRepId: b}); // Caller attribution must never override the source invoice.
  const dashboard = (uid, from = 0, to = Date.now()) => getDashboardSnapshot.run({auth: {uid}, data: {companyId, from, to}});
  return {companyId, admin, a, b, seller, item, ref, rows, draft, transfer, returned, dashboard};
}
async function reconcile(f) {
  const entries = await f.rows("financial_ledger_entries");
  const balances = new Map();
  for (const entry of entries) {
    balances.set(entry.debitAccountKey, (balances.get(entry.debitAccountKey) || 0) + entry.amount);
    balances.set(entry.creditAccountKey, (balances.get(entry.creditAccountKey) || 0) - entry.amount);
    await reconcileFinancialLedgerProjection(db, f.companyId, entry.id);
    await reconcileFinancialLedgerProjection(db, f.companyId, entry.id); // Delivery replay.
  }
  assert.equal([...balances.values()].reduce((n, value) => n + value, 0), 0);
  for (const cash of await f.rows("cash_balances")) {
    const key = cash.cashAccount === "rep_cash" ? `rep_cash:${cash.salesRepId}` : "company_cash";
    assert.equal(balances.get(key) || 0, cash.amount);
  }
  const statement = await f.rows("customer_transactions");
  const balance = statement.reduce((sum, row) => sum + row.debitAmount - row.creditAmount, 0);
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, balance);
  const summary = await getFinancialLedgerSummary.run({auth: {uid: f.admin}, data: {companyId: f.companyId, from: 0, to: Date.now()}});
  assert.equal(summary.metricSales, (await f.dashboard(f.admin)).totalSales);
  assert.equal(summary.metricReceivables, balance);
  return entries;
}

test("returns after transfer keep original seller, dates, custody and company totals through partial and full returns", async () => {
  const f = await fixture();
  const original = (await f.ref("invoices", "old").get()).data();
  const historyNames = ["invoices", "customer_transactions", "financial_ledger_entries", "rep_inventory_movements", "cash_movements", "sales_returns"];
  const before = await Promise.all(historyNames.map(f.rows));
  await f.transfer();
  assert.deepEqual(await Promise.all(historyNames.map(f.rows)), before);
  assert.equal((await f.dashboard(f.a)).totalSales, 30);
  assert.equal((await f.dashboard(f.b)).totalSales, 0);
  for (const actor of [f.a, f.b]) await assert.rejects(f.returned(`denied-${actor}`, 1, "credit_customer_balance", actor), (e) => e.code === "permission-denied");
  await f.returned("partial", 1);
  assert.equal((await f.dashboard(f.admin)).totalSales, 20);
  assert.equal((await f.dashboard(f.a)).totalSales, 20);
  assert.equal((await f.dashboard(f.b)).totalSales, 0);
  assert.equal((await f.dashboard(f.admin, saleDate.toMillis(), saleDate.toMillis())).totalSales, 30);
  assert.equal((await f.dashboard(f.a, returnDate.toMillis(), returnDate.toMillis())).totalSales, -10);
  assert.equal((await f.dashboard(f.b, returnDate.toMillis(), returnDate.toMillis())).totalSales, 0);
  assert.equal((await f.returned("partial", 1)).alreadyPosted, true);
  await f.returned("rest", 2);
  await assert.rejects(f.returned("excess", 0.001), (e) => e.code === "failed-precondition");
  const after = (await f.ref("invoices", "old").get()).data();
  for (const key of ["salesRepId", "salesRepName", "grandTotal", "items", "invoiceDate", "createdByUid", "stockSourceSalesRepId"]) assert.deepEqual(after[key], original[key]);
  assert.equal(after.returnedTotal, 30);
  assert.equal((await f.ref("rep_inventory_balances", `${f.a}_${f.item}`).get()).data().quantity, 10);
  assert.equal((await f.ref("rep_inventory_balances", `${f.b}_${f.item}`).get()).exists, false);
  assert.equal((await db.doc(`items/${f.item}`).get()).data().currentStock, 20);
  for (const row of await f.rows("sales_returns")) assert.equal(row.salesRepId, f.a);
  await reconcile(f);
});

test("refund of an old invoice collected by the new rep attributes sales to seller and cash out to collector", async () => {
  const f = await fixture();
  await f.transfer();
  await createReceiptTransaction(db, f.b, f.companyId, "collection", {customerId: "customer", amount: 30, paymentMethod: "cash", receiptDate: returnDate});
  await f.returned("refund", 1, "cash_refund");
  const entries = await reconcile(f);
  const refund = entries.find((e) => e.component === "cash_refund");
  assert.equal(refund.creditAccountKey, `rep_cash:${f.b}`);
  assert.equal(refund.salesRepId, f.b, "Cash-out reporting must follow the actual refunded cash account");
  assert.equal(refund.salesRepName, f.b);
  assert.equal((await f.rows("cash_movements")).find((m) => m.direction === "out").salesRepName, f.b);
  assert.equal(entries.filter((e) => e.salesRepId === f.a).reduce((n, e) => n + e.metricSales, 0), 20);
  assert.equal(entries.filter((e) => e.salesRepId === f.b).reduce((n, e) => n + e.metricSales, 0), 0);
  assert.equal((await f.ref("cash_balances", `rep_${f.b}`).get()).data().amount, 20);
  assert.equal((await f.ref("cash_balances", `rep_${f.a}`).get()).exists, false);
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, 0);
  for (const [uid, sales, cashOut] of [[f.a, 20, 0], [f.b, 0, 10]]) {
    const summary = await getFinancialLedgerSummary.run({auth: {uid: f.admin}, data: {
      companyId: f.companyId, salesRepId: uid, from: 0, to: Date.now(),
    }});
    assert.equal(summary.metricSales, sales);
    assert.equal(summary.metricRepCashOut, cashOut);
  }
  const {runHistoricalLedgerBackfill} = require("../lib/maintenance/rebuild_financial_ledger");
  const audit = await runHistoricalLedgerBackfill({projectId: app.options.projectId, companyId: f.companyId,
    fromText: "", toText: "", apply: false, confirmProject: "", confirmCompany: "", pageSize: 100, maxWrites: 500}, db);
  assert.equal(audit.safeForControlledBackfill, true, JSON.stringify(audit.anomalies));
});

test("mixed collector cash refunds fail atomically and customer credit remains attributed to the seller", async () => {
  const f = await fixture({paid: 10});
  await f.transfer();
  await createReceiptTransaction(db, f.b, f.companyId, "collection", {customerId: "customer", amount: 20, paymentMethod: "cash", receiptDate: returnDate});
  const names = ["customers", "invoices", "sales_returns", "customer_transactions", "cash_movements", "cash_balances", "financial_ledger_entries", "rep_inventory_balances", "rep_inventory_movements"];
  const before = await Promise.all(names.map(f.rows));
  await assert.rejects(f.returned("mixed-refund", 3, "cash_refund"), (e) => e.code === "failed-precondition" && e.message.includes("multiple collection accounts"));
  assert.deepEqual(await Promise.all(names.map(f.rows)), before);
  await f.returned("credit-instead", 3);
  assert.equal((await f.ref("sales_returns", "credit-instead").get()).data().salesRepId, f.a);
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, -30);
  assert.equal((await f.ref("cash_balances", `rep_${f.a}`).get()).data().amount, 10);
  assert.equal((await f.ref("cash_balances", `rep_${f.b}`).get()).data().amount, 20);
  await reconcile(f);
});

test("new sales belong only to the new rep while historical returns reduce only the original seller", async () => {
  const f = await fixture();
  await f.transfer();
  await f.draft("new", f.b);
  await f.ref("invoices", "new").update({items: [{lineId: "new-service", lineType: "custom", itemId: null,
    itemName: "Service", description: "Synthetic service", unit: "service", quantity: 1, unitPrice: 15, discount: 0, taxPercent: 0}]});
  await confirmInvoiceTransaction(db, f.b, f.companyId, "new");
  await f.returned("old-return", 1);
  assert.equal((await f.dashboard(f.admin)).totalSales, 35);
  assert.equal((await f.dashboard(f.a)).totalSales, 20);
  assert.equal((await f.dashboard(f.b)).totalSales, 15);
  await reconcile(f);
});

test("partial payment returns reduce remaining debt before refunding the verified paid portion", async () => {
  const f = await fixture({paid: 10});
  await f.transfer();
  await f.returned("unpaid-part", 1, "cash_refund");
  const first = (await f.ref("sales_returns", "unpaid-part").get()).data();
  assert.equal(first.receivableReduction, 10);
  assert.equal(first.cashRefundAmount, 0);
  await f.returned("paid-part", 2, "cash_refund");
  const second = (await f.ref("sales_returns", "paid-part").get()).data();
  assert.equal(second.receivableReduction, 10);
  assert.equal(second.cashRefundAmount, 10);
  assert.equal((await f.ref("cash_balances", `rep_${f.a}`).get()).data().amount, 0);
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, 0);
  await reconcile(f);
});

for (const adminSale of [false, true]) test(`${adminSale ? "company" : "representative"} sale refund after reassignment follows original collection and stock`, async () => {
  const f = await fixture({adminSale, paid: 30});
  await f.transfer();
  await f.returned("cash", 1, "cash_refund");
  await f.returned("credit", 2);
  const returns = await f.rows("sales_returns");
  assert.ok(returns.every((r) => r.salesRepId === f.seller));
  assert.equal((await f.dashboard(f.admin)).totalSales, 0);
  assert.equal((await f.dashboard(f.b)).totalSales, 0);
  const cashId = adminSale ? "company_cash" : `rep_${f.a}`;
  assert.equal((await f.ref("cash_balances", cashId).get()).data().amount, 20);
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, -20);
  assert.equal((await db.doc(`items/${f.item}`).get()).data().currentStock, 20);
  await reconcile(f);
});
