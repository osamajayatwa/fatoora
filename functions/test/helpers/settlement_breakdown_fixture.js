"use strict";
const {randomUUID} = require("node:crypto");
const {Timestamp, FieldValue} = require("firebase-admin/firestore");
const {confirmInvoiceTransaction} = require("../../lib/trusted/confirm_invoice");
const {createReceiptTransaction} = require("../../lib/trusted/create_receipt");
const {confirmSalesReturnTransaction} = require("../../lib/trusted/confirm_sales_return");
const {createExpenseTransaction, approveExpenseTransaction} = require("../../lib/trusted/expenses");
const {cancelReceiptTransaction} = require("../../lib/trusted/cancel_receipt");
const {recordCashSettlementTransaction} = require("../../lib/trusted/record_cash_settlement");
const {settlementBreakdownTransaction} = require("../../lib/trusted/settlement_breakdown");
const date = Timestamp.fromDate(new Date("2026-08-05T12:00:00Z"));
const time = t => ({seconds: t.seconds, nanoseconds: t.nanoseconds});
async function breakdownFixture(db, {opening = true, legacyCurrency = true} = {}) {
  const companyId = `breakdown-${randomUUID()}`, admin = `${companyId}-admin`, rep = `${companyId}-rep`, other = `${companyId}-other`;
  const c = `companies/${companyId}`, bookId = "synthetic-book", b = `${c}/books/${bookId}`;
  const ref = (collection, id) => db.doc(`${c}/${collection}/${id}`);
  const batch = db.batch();batch.create(db.doc(c), {id: companyId, active: true, activeBookId: bookId});
  batch.create(db.doc(b), {id: bookId, companyId, bookId, approvalStatus: "approved", currency: "JOD", moneyScale: 3, journalPostingEnabled: false,
    ...(legacyCurrency ? {cashEvidenceCurrencyBindingId: "cash-ledger-v1"} : {})});
  if (legacyCurrency) batch.create(db.doc(`${b}/currency_bindings/cash-ledger-v1`), {id: "cash-ledger-v1", revisionId: "cash-ledger-v1", companyId, bookId,
    approvalStatus: "approved", currency: "JOD", moneyScale: 3, sourceCollection: "cash_movements", scope: "company_cash_ledger"});
  for (const [uid, role] of [[admin, "admin"], [rep, "sales_rep"], [other, "sales_rep"]]) batch.create(db.doc(`users/${uid}`), {uid, companyId, name: uid, role, active: true, approvalStatus: "approved"});
  batch.create(ref("customers", "customer"), {id: "customer", companyId, name: "Synthetic", active: true, createdByUid: rep,
    assignedToUid: rep, assignmentVersion: 1, assignmentRevision: 0, currentBalance: 0, totalSales: 0, totalPaid: 0});
  await batch.commit();
  const seed = db.batch();
  for (const [account, owner, amount] of [["rep_cash", rep, 100.111], ["company_cash", "", 20.222]]) {
    const accountId = account === "rep_cash" ? `rep_${owner}` : "company_cash", id = `${accountId}_opening`;
    if (opening) seed.create(ref("cash_movements", id), {id, companyId, cashAccount: account, salesRepId: owner, type: "opening_balance", movementType: "opening_balance",
      direction: "in", amount, balanceBefore: 0, balanceAfter: amount, date, movementDate: date, sourceCollection: "cash_movements", sourceId: id, referenceId: id,
      sourceNumber: "SYNTHETIC-OPENING", immutable: true, createdByUid: admin, createdByName: admin, createdByRole: "admin", createdAt: FieldValue.serverTimestamp()});
    seed.create(ref("cash_balances", accountId), {id: accountId, companyId, cashAccount: account, salesRepId: owner, amount,
      ...(opening ? {lastMovementId: id} : {}), updatedAt: FieldValue.serverTimestamp()});
  }
  await seed.commit();
  const invoice = async (id, {paid = 0, actor = rep, seller = rep, businessDate = date, quantity = 3, price = 10} = {}) => {
    await ref("invoices", id).create({id, companyId, invoiceNumber: `INV-${id}`, invoiceDate: businessDate, dueDate: businessDate,
      customerId: "customer", customerSnapshot: {id: "customer", name: "Synthetic"}, createdByUid: actor, createdByName: actor, createdByRole: actor === admin ? "admin" : "sales_rep",
      salesRepId: seller, salesRepName: seller, invoiceStatus: "draft", isLocked: false, financialPosted: false, inventoryPosted: false,
      paidAmount: paid, hasReceivedPayment: paid > 0, stockSourceType: actor === admin ? "companyWarehouse" : "salesRep", stockSourceSalesRepId: actor === admin ? "" : seller,
      items: [{lineId: "line", lineType: "custom", itemId: null, itemName: "Synthetic service", description: "Synthetic service", unit: "piece", quantity, unitPrice: price, discount: 0, taxPercent: 0}]});
    return confirmInvoiceTransaction(db, actor, companyId, id);
  };
  const receipt = (key, amount, actor = rep, method = "cash") => createReceiptTransaction(db, actor, companyId, `receipt-key-${key}`,
    {customerId: "customer", amount, paymentMethod: method, receiptDate: date});
  const refund = (id, originalInvoiceId, quantity = 1, refundType = "cash_refund") => confirmSalesReturnTransaction(db, admin, companyId, id,
    {originalInvoiceId, returnDate: date, reason: "Synthetic", refundType, items: [{originalInvoiceItemId: `${originalInvoiceId}:line:line`, returnedQuantity: quantity}]});
  const expense = async (key, amount, fundingSource = "rep_collected_cash", approve = true, actor = rep) => {
    const result = await createExpenseTransaction(db, actor, companyId, `expense-key-${key}`, {amount, category: "fuel", description: "Synthetic", fundingSource, expenseDate: date});
    if (approve && actor !== admin) await approveExpenseTransaction(db, admin, companyId, result.expenseId);return result;
  };
  const settle = (key, amount = 1) => recordCashSettlementTransaction(db, admin, companyId, `settlement-key-${key}`, {salesRepId: rep, amount, settlementDate: date, notes: "Synthetic"});
  const breakdown = (settlementId, overrides = {}, viewer = admin, database = db) => settlementBreakdownTransaction(database, viewer,
    {companyId, salesRepId: rep, settlementId, ...overrides}, {enableEmulatorBreakdown: true});
  const preview = async (overrides = {}, viewer = admin, database = db) => {
    const observation = await db.doc(c).get();return settlementBreakdownTransaction(database, viewer,
      {companyId, salesRepId: rep, committedThrough: time(observation.readTime), ...overrides}, {enableEmulatorBreakdown: true});
  };
  return {companyId, admin, rep, other, c, b, bookId, ref, invoice, receipt, refund, expense, settle, breakdown, preview,
    cancel: receiptId => cancelReceiptTransaction(db, admin, companyId, receiptId, "Synthetic cancellation"), date};
}
module.exports = {breakdownFixture, date, time};
