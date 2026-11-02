"use strict";
const assert = require("node:assert/strict");
const {before, after, test} = require("node:test");
// This suite must never fall back to Application Default Credentials.
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) {
  throw new Error("Integrity tests require a loopback Firestore emulator.");
}
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {confirmInvoiceTransaction} = require("../lib/trusted/confirm_invoice");
const {confirmInventoryTransferTransaction} = require("../lib/trusted/confirm_inventory_transfer");
const {confirmSalesReturnTransaction} = require("../lib/trusted/confirm_sales_return");
const {createItemTransaction, adjustStockTransaction} = require("../lib/trusted/inventory");
const {createReceiptTransaction} = require("../lib/trusted/create_receipt");
const {recordCashSettlementTransaction} = require("../lib/trusted/record_cash_settlement");
const {projectItemReportingFields} = require("../lib/trusted/operational_search_projection");
const {calculateInvoiceLine} = require("../lib/trusted/totals");
const {createExpenseTransaction, approveExpenseTransaction} = require("../lib/trusted/expenses");
const {cancelReceiptTransaction} = require("../lib/trusted/cancel_receipt");
const {COLLECTIONS, reconcileSnapshot} = require("../scripts/integrity_reconciliation");
const {reconcileFinancialLedgerProjection, getFinancialLedgerSummary} = require("../lib/trusted/financial_ledger_reporting");
const app = initializeApp({projectId: "demo-fatoora-integrity-regression"});
const db = getFirestore(app);
before(async () => {
  const result = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-fatoora-integrity-regression/databases/(default)/documents`, {method: "DELETE"});
  assert.ok(result.ok);
});
after(() => deleteApp(app));
const date = Timestamp.fromDate(new Date("2026-11-02T08:00:00Z"));

test("decimal half-thousandth product rounds exactly", () => {
  const line = calculateInvoiceLine({lineType: "custom", quantity: 0.41, unitPrice: 4.35, discount: 0, taxPercent: 0}, 0);
  assert.equal(line.subtotal, 1.784);
});

async function fixture(name, {rep = false, lines, paid = 0} = {}) {
  const company = `integrity-${name}`;
  const admin = `${name}-admin`, owner = rep ? `${name}-rep` : admin;
  const item = `${name}-item`;
  const ref = (collection, id) => db.doc(`companies/${company}/${collection}/${id}`);
  const batch = db.batch();
  for (const [uid, role] of [[admin, "admin"], ...(rep ? [[owner, "sales_rep"]] : [])]) {
    batch.set(db.doc(`users/${uid}`), {uid, role, name: uid, companyId: company,
      active: true, approvalStatus: "approved"});
  }
  batch.set(ref("customers", "customer"), {id: "customer", companyId: company,
    name: "Synthetic customer", active: true, createdByUid: owner,
    currentBalance: 0, totalPaid: 0, totalSales: 0});
  batch.set(db.doc(`items/${item}`), {id: item, companyId: company, name: item,
    code: item, unit: "pcs", active: true, deleted: false, trackStock: true,
    currentStock: 20, costPrice: 2});
  if (rep) batch.set(ref("rep_inventory_balances", `${owner}_${item}`), {
    id: `${owner}_${item}`, companyId: company, salesRepId: owner, itemId: item, quantity: 10,
  });
  const invoiceLines = lines || [{lineId: "line-1", lineType: "catalog", itemId: item,
    itemName: item, unit: "pcs", quantity: 3, unitPrice: 10, discount: 0, taxPercent: 0}];
  batch.set(ref("invoices", "sale"), {id: "sale", companyId: company,
    invoiceNumber: `INV-${name}`, invoiceDate: date, dueDate: date,
    customerId: "customer", customerSnapshot: {id: "customer", name: "Synthetic customer"},
    createdByUid: owner, createdByName: owner, createdByRole: rep ? "sales_rep" : "admin",
    salesRepId: owner, salesRepName: owner, invoiceStatus: "draft", isLocked: false,
    financialPosted: false, inventoryPosted: false, items: invoiceLines,
    stockSourceType: rep ? "salesRep" : "companyWarehouse",
    stockSourceSalesRepId: rep ? owner : "", paidAmount: paid, hasReceivedPayment: paid > 0,
  });
  await batch.commit();
  const post = () => confirmInvoiceTransaction(db, owner, company, "sale");
  const returned = (id, quantity, line = "line-1") => confirmSalesReturnTransaction(
    db, owner, company, id, {originalInvoiceId: "sale", returnDate: date,
      reason: "Synthetic return", refundType: "credit_customer_balance",
      items: [{originalInvoiceItemId: `sale:line:${line}`, returnedQuantity: quantity}]});
  return {company, admin, owner, item, ref, post, returned};
}

async function transfer(f, id, lines, type = "warehouseToRep") {
  await f.ref("inventory_transfers", id).set({id, companyId: f.company,
    transferNumber: id, salesRepId: f.owner, type, status: "draft", lines});
  return () => confirmInventoryTransferTransaction(db, f.admin, f.company, id);
}

test("representative sale deducts custody only, including replay after success", async () => {
  const f = await fixture("custody", {rep: true, paid: 10});
  assert.equal((await f.post()).alreadyPosted, false);
  assert.equal((await f.post()).alreadyPosted, true);
  assert.equal((await db.doc(`items/${f.item}`).get()).data().currentStock, 20);
  assert.equal((await f.ref("rep_inventory_balances", `${f.owner}_${f.item}`).get()).data().quantity, 7);
  assert.equal((await f.ref("cash_balances", `rep_${f.owner}`).get()).data().amount, 10);
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, 20);
  assert.equal((await db.collection(`companies/${f.company}/rep_inventory_movements`).get()).size, 1);
});

test("duplicate transfer items are rejected without any stock effects", async () => {
  const f = await fixture("duplicate", {rep: true});
  const post = await transfer(f, "duplicate", [{itemId: f.item, quantity: 2}, {itemId: f.item, quantity: 3}]);
  await assert.rejects(post, (e) => e.code === "invalid-argument" && e.details?.reason === "duplicate-item");
  assert.equal((await db.doc(`items/${f.item}`).get()).data().currentStock, 20);
  assert.equal((await f.ref("inventory_transfers", "duplicate").get()).data().status, "draft");
  assert.equal((await db.collection(`companies/${f.company}/stock_movements`).get()).size, 0);
});

test("journal collision aborts the complete invoice instead of overwriting history", async () => {
  const f = await fixture("collision");
  const original = {id: "invoice_sale_sales_receivable", companyId: f.company, amount: 123, marker: "preserve"};
  await f.ref("financial_ledger_entries", original.id).set(original);
  await assert.rejects(f.post);
  assert.deepEqual((await f.ref("financial_ledger_entries", original.id).get()).data(), original);
  assert.equal((await db.doc(`items/${f.item}`).get()).data().currentStock, 20);
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, 0);
});

for (const operation of ["invoice", "transfer"]) test(`${operation} rejects another company's catalog stock`, async () => {
  const f = await fixture(`foreign-${operation}`, {rep: true});
  await db.doc(`items/${f.item}`).update({companyId: "another-company"});
  const post = operation === "invoice" ? f.post : await transfer(f, "foreign", [{itemId: f.item, quantity: 2}]);
  await assert.rejects(post, (e) => ["failed-precondition", "permission-denied"].includes(e.code));
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, 0);
});

test("malformed or mismatched custody is never silently replaced by a balance", async () => {
  const f = await fixture("bad-custody", {rep: true});
  await f.ref("rep_inventory_balances", `${f.owner}_${f.item}`).update({salesRepId: "another-rep"});
  await assert.rejects(f.post, (e) => e.code === "data-loss");
  assert.equal((await f.ref("invoices", "sale").get()).data().invoiceStatus, "draft");
});

test("disabled catalog tracking cannot silently bypass existing custody", async () => {
  const f = await fixture("tracking-disabled", {rep: true});
  await db.doc(`items/${f.item}`).update({trackStock: false, currentStock: 0});
  await assert.rejects(f.post, (e) => e.code === "failed-precondition");
  assert.equal((await f.ref("invoices", "sale").get()).data().invoiceStatus, "draft");
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, 0);
});

test("malformed cash balance fails closed without inventing cash", async () => {
  const f = await fixture("bad-cash", {paid: 10});
  await f.ref("cash_balances", "company_cash").set({cashAccount: "company_cash", salesRepId: "", amount: "corrupt"});
  await assert.rejects(f.post, (e) => e.code === "data-loss");
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, 0);
});

test("malformed receivable is never silently reset to zero", async () => {
  const f = await fixture("bad-receivable");
  await f.ref("customers", "customer").update({currentBalance: "corrupt"});
  await assert.rejects(f.post, (e) => e.code === "data-loss");
  assert.equal((await db.doc(`items/${f.item}`).get()).data().currentStock, 20);
});

test("missing custody projection with movement history cannot restart at zero", async () => {
  const f = await fixture("missing-custody", {rep: true});
  const deliver = await transfer(f, "delivery-one", [{itemId: f.item, quantity: 2}]);
  await deliver();
  await f.ref("rep_inventory_balances", `${f.owner}_${f.item}`).delete();
  const deliverAgain = await transfer(f, "delivery-two", [{itemId: f.item, quantity: 1}]);
  await assert.rejects(deliverAgain, (e) => e.code === "data-loss");
  assert.equal((await db.doc(`items/${f.item}`).get()).data().currentStock, 18);
});

test("simultaneous sales cannot both consume the same custody", async () => {
  const f = await fixture("concurrent-sales", {rep: true});
  const sale = (await f.ref("invoices", "sale").get()).data();
  const items = sale.items.map((line) => ({...line, quantity: 7}));
  await f.ref("invoices", "sale").update({items});
  await f.ref("invoices", "sale-2").set({...sale, id: "sale-2", items});
  const results = await Promise.allSettled([f.post(), confirmInvoiceTransaction(db, f.owner, f.company, "sale-2")]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal((await f.ref("rep_inventory_balances", `${f.owner}_${f.item}`).get()).data().quantity, 3);
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, 70);
});

test("split returns allocate the original amount exactly, including rounding residuals", async () => {
  const f = await fixture("rounding", {lines: [{lineId: "line-1", lineType: "custom", itemId: null,
    itemName: "Service", unit: "pcs", description: "Synthetic service", quantity: 3,
    unitPrice: 0.333, discount: 0.001, taxPercent: 0}]});
  await f.post();
  for (let i = 0; i < 3; i++) await f.returned(`return-${i}`, 1);
  const sale = (await f.ref("invoices", "sale").get()).data();
  assert.equal(sale.grandTotal, 0.998);
  assert.equal(sale.returnedTotal, 0.998);
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, 0);
});

test("free tracked lines can be returned without zero-valued financial journals", async () => {
  const f = await fixture("free-return");
  const sale = (await f.ref("invoices", "sale").get()).data();
  await f.ref("invoices", "sale").update({items: [...sale.items, {...sale.items[0], lineId: "free", quantity: 1, unitPrice: 0}]});
  await f.post();
  await f.returned("free-return", 1, "free");
  assert.equal((await db.doc(`items/${f.item}`).get()).data().currentStock, 17);
  assert.equal((await f.ref("sales_returns", "free-return").get()).data().grandTotal, 0);
  const entries = await db.collection(`companies/${f.company}/financial_ledger_entries`).get();
  assert.equal(entries.size, 1);
});

test("missing referenced sale movement prevents a return from silently skipping inventory", async () => {
  const f = await fixture("missing-movement");
  await f.post();
  const sale = (await f.ref("invoices", "sale").get()).data();
  await f.ref("stock_movements", sale.inventoryMovementIds[0]).delete();
  await assert.rejects(() => f.returned("return", 1), (e) => e.code === "data-loss");
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, 30);
});

test("item creation replay survives later stock movements", async () => {
  const uid = "integrity-item-admin", company = "default_company", key = "integrity-create-item";
  await db.doc(`users/${uid}`).set({uid, role: "admin", companyId: company, active: true, approvalStatus: "approved"});
  const input = {name: "Synthetic", code: "SYN", description: "Synthetic", unit: "pcs",
    price: 10, taxRate: 0, currentStock: 5, openingStock: 5, minStock: 0, costPrice: 1, trackStock: true};
  const first = await createItemTransaction(db, uid, company, key, input);
  await adjustStockTransaction(db, uid, company, "integrity-adjust-item", {itemId: first.itemId,
    adjustmentType: "increase_stock", quantity: 2, notes: "Synthetic inbound"});
  assert.equal((await createItemTransaction(db, uid, company, key, input)).alreadyPosted, true);
  assert.equal((await db.doc(`items/${first.itemId}`).get()).data().currentStock, 7);
  await assert.rejects(() => createItemTransaction(db, uid, company, key, {...input, price: 11}), (e) => e.code === "already-exists");
});

test("delayed item reporting event uses current stock and current name", async () => {
  const f = await fixture("stale-projection");
  const ref = db.doc(`items/${f.item}`), old = await ref.get();
  await ref.update({currentStock: 0, name: "Current name"});
  await projectItemReportingFields.run({data: {after: old}});
  const current = (await ref.get()).data();
  assert.equal(current.stockStatus, "out");
  assert.equal(current.inventoryValue, 0);
  assert.equal(current.nameLower, "current name");
});

test("representative cannot confirm a warehouse-sourced draft", async () => {
  const f = await fixture("unauthorized", {rep: true});
  await f.ref("invoices", "sale").update({stockSourceType: "companyWarehouse", stockSourceSalesRepId: ""});
  await assert.rejects(f.post, (e) => e.code === "permission-denied");
});

test("receipts and linked settlement conserve cash and receivables", async () => {
  const f = await fixture("collections", {rep: true, paid: 10});
  await f.post();
  const input = {customerId: "customer", amount: 20, receiptDate: date, paymentMethod: "cash"};
  const receipt = await createReceiptTransaction(db, f.owner, f.company, "integrity-receipt", input);
  assert.equal((await createReceiptTransaction(db, f.owner, f.company, "integrity-receipt", input)).alreadyPosted, true);
  assert.ok(receipt.receiptId);
  await recordCashSettlementTransaction(db, f.admin, f.company, "integrity-settlement", {
    salesRepId: f.owner, amount: 30, settlementDate: date});
  assert.equal((await f.ref("cash_balances", "company_cash").get()).data().amount, 30);
  assert.equal((await f.ref("cash_balances", `rep_${f.owner}`).get()).data().amount, 0);
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, 0);
});

test("legacy return rounding discrepancy blocks further posting without compensating silently", async () => {
  const f = await fixture("legacy-return-rounding", {lines: [{lineId: "line-1", lineType: "custom", itemId: null,
    itemName: "Service", unit: "pcs", description: "Synthetic", quantity: 3, unitPrice: 0.333, discount: 0.001, taxPercent: 0}]});
  await f.post();
  await f.ref("sales_returns", "legacy").set({id: "legacy", companyId: f.company, originalInvoiceId: "sale", status: "confirmed", financialPosted: true,
    grandTotal: 0.666, items: [{originalInvoiceItemId: "sale:line:line-1", returnedQuantity: 2, total: 0.666}]});
  await f.ref("invoices", "sale").update({returnedQuantitiesByItem: {"sale:line:line-1": 2}, returnedTotal: 0.666, returnedReceivableAmount: 0.666});
  await f.ref("customers", "customer").update({currentBalance: 0.332});
  await assert.rejects(() => f.returned("next", 1), (e) => e.code === "data-loss");
  assert.equal((await f.ref("customers", "customer").get()).data().currentBalance, 0.332);
  assert.equal((await f.ref("sales_returns", "next").get()).exists, false);
});

test("incomplete returned-quantity projection cannot permit an over-return", async () => {
  const f = await fixture("incomplete-return-cache");
  await f.post(); await f.returned("first", 1);
  await f.ref("invoices", "sale").update({returnedQuantitiesByItem: {"sale:line:line-1": 0}});
  await assert.rejects(() => f.returned("second", 3), (e) => e.code === "data-loss");
  assert.equal((await db.doc(`items/${f.item}`).get()).data().currentStock, 18);
});

test("complete trusted lifecycle independently reconciles sources, balances, journals and summary", async () => {
  const company = "default_company", admin = "lifecycle-admin", rep = "lifecycle-rep";
  const ref = (collection, id) => db.doc(`companies/${company}/${collection}/${id}`);
  for (const [uid, role] of [[admin, "admin"], [rep, "sales_rep"]]) await db.doc(`users/${uid}`).set({
    uid, role, name: uid, companyId: company, active: true, approvalStatus: "approved"});
  const item = (await createItemTransaction(db, admin, company, "lifecycle-item", {
    name: "Synthetic pump", code: "SYN-LIFE", description: "Synthetic", unit: "pcs", price: 10,
    taxRate: 0, currentStock: 20, openingStock: 20, minStock: 1, costPrice: 2, trackStock: true,
  })).itemId;
  await ref("customers", "life-customer").set({id: "life-customer", companyId: company, name: "Synthetic",
    createdByUid: rep, active: true, currentBalance: 0, totalSales: 0, totalPaid: 0});
  for (const [id, type, quantity] of [["life-delivery", "warehouseToRep", 8]]) {
    await ref("inventory_transfers", id).set({id, companyId: company, transferNumber: id,
      type, status: "draft", salesRepId: rep, lines: [{itemId: item, quantity}]});
    await confirmInventoryTransferTransaction(db, admin, company, id);
  }
  await ref("invoices", "life-sale").set({id: "life-sale", companyId: company, invoiceNumber: "SYN-LIFE", invoiceDate: date, dueDate: date,
    invoiceStatus: "draft", financialPosted: false, inventoryPosted: false, customerId: "life-customer",
    customerSnapshot: {id: "life-customer", name: "Synthetic"}, createdByUid: rep, createdByRole: "sales_rep",
    salesRepId: rep, salesRepName: rep, stockSourceType: "salesRep", stockSourceSalesRepId: rep,
    hasReceivedPayment: true, paidAmount: 10, items: [{lineId: "life-line", lineType: "catalog", itemId: item,
      itemName: "Synthetic pump", unit: "pcs", quantity: 3, unitPrice: 10, discount: 0, taxPercent: 0}]});
  await confirmInvoiceTransaction(db, rep, company, "life-sale");
  await createReceiptTransaction(db, rep, company, "life-receipt", {customerId: "life-customer", amount: 20, paymentMethod: "cash", receiptDate: date});
  await confirmSalesReturnTransaction(db, rep, company, "life-return", {originalInvoiceId: "life-sale", returnDate: date,
    refundType: "credit_customer_balance", reason: "Synthetic return", items: [{originalInvoiceItemId: "life-sale:line:life-line", returnedQuantity: 1}]});
  await ref("inventory_transfers", "life-stock-return").set({id: "life-stock-return", companyId: company, transferNumber: "SYN-RETURN",
    type: "repToWarehouse", status: "draft", salesRepId: rep, lines: [{itemId: item, quantity: 2}]});
  await confirmInventoryTransferTransaction(db, admin, company, "life-stock-return");
  for (const [key, fundingSource, spent] of [["life-personal", "personal_cash", 1], ["life-fuel", "rep_collected_cash", 2]]) {
    const expense = await createExpenseTransaction(db, rep, company, key, {amount: spent, category: "fuel", fundingSource, expenseDate: date});
    await approveExpenseTransaction(db, admin, company, expense.expenseId);
  }
  await recordCashSettlementTransaction(db, admin, company, "life-settlement", {salesRepId: rep, amount: 20, settlementDate: date});
  await createExpenseTransaction(db, admin, company, "life-office", {amount: 3, category: "office", fundingSource: "company_cash", expenseDate: date});
  // Cancellation reverses a clearing collection and retains the original event.
  await ref("customers", "life-opening-customer").set({id: "life-opening-customer", companyId: company, name: "Synthetic opening",
    createdByUid: admin, active: true, currentBalance: 0, totalSales: 0, totalPaid: 0});
  const {postOpeningBalanceTransaction} = require("../lib/trusted/post_opening_balance");
  await postOpeningBalanceTransaction(db, admin, company, "life-opening-customer", {openingBalanceType: "customer_owes", amount: 10, transactionDate: date});
  const receipt = await createReceiptTransaction(db, admin, company, "life-bank-receipt", {customerId: "life-opening-customer", amount: 10, paymentMethod: "bank", receiptDate: date});
  await cancelReceiptTransaction(db, admin, company, receipt.receiptId, "Synthetic cancellation");
  const collections = {};
  for (const name of COLLECTIONS) {
    const query = name === "items" ? db.collection(name).where("companyId", "==", company) : db.collection(`companies/${company}/${name}`);
    collections[name] = (await query.get()).docs.map((doc) => ({...doc.data(), id: doc.id}));
  }
  for (const entry of collections.financial_ledger_entries) {
    await reconcileFinancialLedgerProjection(db, company, entry.id);
    await reconcileFinancialLedgerProjection(db, company, entry.id); // at-least-once delivery
  }
  const summary = await getFinancialLedgerSummary.run({auth: {uid: admin}, data: {companyId: company,
    from: "2026-01-01T00:00:00Z", to: "2026-12-31T23:59:59.999Z"}});
  const snapshot = {companyId: company, fullHistory: true, collections, reportTotals: {
    sales: summary.metricSales, receipts: summary.metricReceipts, returns: summary.metricReturns,
    expenses: summary.metricExpenses, settlements: summary.metricSettlements}};
  const result = reconcileSnapshot(snapshot);
  const {writeFileSync, mkdirSync} = require("node:fs"), {join} = require("node:path");
  const output = join(__dirname, "..", "..", "output", "integrity-audit");
  mkdirSync(output, {recursive: true});
  writeFileSync(join(output, "synthetic-lifecycle-snapshot.json"), JSON.stringify(snapshot, null, 2));
  writeFileSync(join(output, "synthetic-lifecycle-reconciliation.json"), JSON.stringify(result, null, 2));
  assert.deepEqual(result.issues, []);
  assert.deepEqual(result.warnings, []);
  assert.equal(result.status, "PASS");
  assert.equal((await ref("cash_balances", "company_cash").get()).data().amount, 17);
  assert.equal((await ref("cash_balances", `rep_${rep}`).get()).data().amount, 8);
  assert.equal((await ref("rep_inventory_balances", `${rep}_${item}`).get()).data().quantity, 4);
});
