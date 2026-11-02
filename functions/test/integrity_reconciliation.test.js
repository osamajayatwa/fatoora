"use strict";
const assert = require("node:assert/strict");
const {test} = require("node:test");
const {COLLECTIONS, reconcileSnapshot} = require("../scripts/integrity_reconciliation");

function fixture() {
  const collections = Object.fromEntries(COLLECTIONS.map((name) => [name, []]));
  const snapshot = {companyId: "synthetic", fullHistory: true, collections,
    reportTotals: {sales: 20, receipts: 20, returns: 10, expenses: 0, settlements: 30}};
  const put = (name, row) => collections[name].push({companyId: "synthetic", ...row});
  put("items", {id: "pump", currentStock: 6});
  put("rep_inventory_balances", {id: "rep_pump", salesRepId: "rep", itemId: "pump", quantity: 2});
  put("customers", {id: "customer", currentBalance: -10});
  put("invoices", {id: "sale", invoiceStatus: "confirmed", financialPosted: true, inventoryPosted: true,
    stockSourceType: "salesRep", stockSourceSalesRepId: "rep", salesRepId: "rep", customerId: "customer", grandTotal: 30,
    items: [{lineId: "one", lineType: "catalog", itemId: "pump", quantity: 3, total: 30, stockTrackedAtPosting: true}], inventoryMovementIds: ["sale-stock"]});
  put("inventory_transfers", {id: "transfer", status: "confirmed", type: "warehouseToRep", salesRepId: "rep", lines: [{itemId: "pump", quantity: 4}]});
  put("stock_movements", {id: "opening", itemId: "pump", direction: "in", quantity: 10, quantityBefore: 0, quantityAfter: 10, referenceType: "item", referenceId: "pump"});
  put("stock_movements", {id: "warehouse-transfer", itemId: "pump", direction: "out", quantity: 4, quantityBefore: 10, quantityAfter: 6, referenceType: "inventory_transfer", referenceId: "transfer"});
  for (const row of [
    {id: "rep-transfer", direction: "in", quantity: 4, quantityBefore: 0, quantityAfter: 4, referenceType: "inventoryTransfer", referenceId: "transfer"},
    {id: "sale-stock", direction: "out", quantity: 3, quantityBefore: 4, quantityAfter: 1, referenceType: "invoice", referenceId: "sale"},
    {id: "return-stock", direction: "in", quantity: 1, quantityBefore: 1, quantityAfter: 2, referenceType: "salesReturn", referenceId: "return", sourceLineIndex: 0},
  ]) put("rep_inventory_movements", {...row, salesRepId: "rep", itemId: "pump"});
  put("receipts", {id: "receipt", customerId: "customer", amount: 20, paymentMethod: "cash", createdByRole: "sales_rep", createdByUid: "rep", invoiceAllocations: {sale: 20}});
  put("sales_returns", {id: "return", customerId: "customer", status: "confirmed", financialPosted: true, originalInvoiceId: "sale", grandTotal: 10,
    items: [{lineType: "catalog", originalIndex: 0, itemId: "pump", returnedQuantity: 1, total: 10}]});
  put("settlements", {id: "settlement", status: "posted", amount: 30, salesRepId: "rep"});
  for (const [id, debitAmount, creditAmount] of [["sale", 30, 0], ["payment", 0, 10], ["receipt", 0, 20], ["return", 0, 10]]) {
    put("customer_transactions", {id, customerId: "customer", debitAmount, creditAmount});
  }
  for (const row of [
    {id: "sale_cash", direction: "in", amount: 10, balanceBefore: 0, balanceAfter: 10, sourceCollection: "invoices", sourceId: "sale"},
    {id: "receipt-cash", direction: "in", amount: 20, balanceBefore: 10, balanceAfter: 30, sourceCollection: "receipts", sourceId: "receipt"},
    {id: "settlement-rep", direction: "out", amount: 30, balanceBefore: 30, balanceAfter: 0, sourceCollection: "settlements", sourceId: "settlement"},
  ]) put("cash_movements", {...row, cashAccount: "rep_cash", salesRepId: "rep"});
  put("cash_movements", {id: "settlement-company", direction: "in", amount: 30, balanceBefore: 0, balanceAfter: 30, sourceCollection: "settlements", sourceId: "settlement", cashAccount: "company_cash", salesRepId: ""});
  put("cash_balances", {id: "rep_rep", amount: 0});
  put("cash_balances", {id: "company_cash", amount: 30});
  const entry = (id, amount, debitAccountKey, creditAccountKey, metrics) => put("financial_ledger_entries", {id, amount, debitAccountKey, creditAccountKey, ...metrics});
  entry("sale-paid", 10, "rep_cash:rep", "sales", {metricSales: 10});
  entry("sale-credit", 20, "customer:customer", "sales", {metricSales: 20});
  entry("receipt", 20, "rep_cash:rep", "customer:customer", {metricReceipts: 20});
  entry("return", 10, "sales", "customer:customer", {metricSales: -10, metricReturns: 10});
  entry("settlement", 30, "company_cash", "rep_cash:rep", {metricSettlements: 30});
  return snapshot;
}

test("independent stock, cash, AR, source journals and report totals reconcile", () => {
  const result = reconcileSnapshot(fixture());
  assert.deepEqual(result.issues, []);
  assert.deepEqual(result.warnings, []);
  assert.equal(result.status, "PASS");
  assert.ok(result.checks.length >= 20);
});

for (const [name, mutate, code] of [
  ["missing custody deduction", (s) => s.collections.rep_inventory_movements.splice(1, 1), "invoice-stock:pump"],
  ["incorrect custody balance", (s) => s.collections.rep_inventory_balances[0].quantity = 99, "balance-from-movements"],
  ["duplicate movement identity", (s) => s.collections.rep_inventory_movements.push({...s.collections.rep_inventory_movements[0]}), "duplicate-or-missing-identity"],
  ["missing settlement destination", (s) => s.collections.cash_movements.pop(), "unpaired-cash-settlement"],
  ["balanced journal on wrong account", (s) => s.collections.financial_ledger_entries[2].debitAccountKey = "company_cash", "general-ledger-cash"],
  ["phantom customer cash collection", (s) => s.collections.customers[0].currentBalance = -20, "receivable-from-sources"],
  ["report discrepancy", (s) => s.reportTotals.sales = 999, "export-metric:sales"],
  ["invalid monetary precision", (s) => s.collections.cash_balances[0].amount = 0.0001, "invalid-source-data"],
]) test(`reconciliation detects ${name}`, () => {
  const snapshot = fixture(); mutate(snapshot);
  const result = reconcileSnapshot(snapshot);
  assert.equal(result.status, "FAIL");
  assert.ok(result.issues.some((i) => i.code === code), JSON.stringify(result.issues));
  assert.ok(result.issues.every((i) => i.path && i.repair));
});

test("partial history and missing tracking provenance are explicitly BLOCKED", () => {
  const snapshot = fixture(); snapshot.fullHistory = false;
  delete snapshot.collections.invoices[0].items[0].stockTrackedAtPosting;
  const result = reconcileSnapshot(snapshot);
  assert.equal(result.status, "BLOCKED");
  assert.equal(result.warnings.length, 2);
});

test("reconciliation never mutates the supplied evidence", () => {
  const snapshot = fixture(), before = JSON.stringify(snapshot);
  reconcileSnapshot(snapshot);
  assert.equal(JSON.stringify(snapshot), before);
});
