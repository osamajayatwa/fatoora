"use strict";
const {FieldValue} = require("firebase-admin/firestore");
const {breakdownFixture} = require("./settlement_breakdown_fixture");

/** Synthetic immutable sequential account commits. Source definitions are
 * batched; each cash movement and its position share a real SDK commit. */
async function volumeFixture(db, count, {mixed = false, participantName} = {}) {
  const f = await breakdownFixture(db);
  const actorName = participantName ?? f.rep;
  let balanceUnits = 100111n;
  if (mixed) {
    await f.invoice("workflow-paid", {paid: 30});await f.refund("workflow-refund", "workflow-paid");
    await f.expense("workflow-expense", 3.125);await f.invoice("receipt-origin");await f.receipt("workflow-receipt", 0.007);
    await f.settle("previous-partial", 0.111);balanceUnits += 20000n - 3125n + 7n - 111n;
  }
  for (let start = 0; start < count; start += 200) {
    const batch = db.batch();
    for (let index = start; index < Math.min(start + 200, count); index++) {
      const id = `volume-${index.toString().padStart(6, "0")}`;
      batch.create(f.ref("invoices", id), {id, companyId: f.companyId, invoiceNumber: `INV-${index}`, invoiceDate: f.date,
        financialPosted: true, invoiceStatus: "confirmed", initialPaidAmount: 0.001, grandTotal: 10, initialCashAccount: "rep_cash", paymentType: "partial",
        cashMovementIds: [`${id}_cash`], receiptIds: [], returnInvoiceIds: [], customerId: "customer", salesRepId: f.rep, salesRepName: actorName,
        createdByUid: f.rep, createdByName: actorName, createdByRole: "sales_rep", financialPostedByUid: f.rep, financialPostedByName: actorName});
    }
    await batch.commit();
  }
  for (let index = 0; index < count; index++) {
    const id = `volume-${index.toString().padStart(6, "0")}`, movementId = `${id}_cash`, batch = db.batch(), after = balanceUnits + 1n;
    batch.create(f.ref("cash_movements", movementId), {id: movementId, companyId: f.companyId, cashAccount: "rep_cash", salesRepId: f.rep,
      movementType: "invoice_payment", type: "invoice_partial", direction: "in", amount: 0.001, balanceBefore: Number(balanceUnits) / 1000, balanceAfter: Number(after) / 1000,
      sourceCollection: "invoices", sourceId: id, sourceNumber: `INV-${index}`, referenceId: id, referenceNumber: `INV-${index}`, customerId: "customer",
      date: f.date, movementDate: f.date, paymentType: "partial", createdByUid: f.rep, createdByName: actorName, createdByRole: "sales_rep", createdAt: FieldValue.serverTimestamp(),
      ...(participantName ? {sellerId: f.rep, sellerName: actorName, postedByUid: f.rep, postedByName: actorName,
        sourceCreatedByUid: f.rep, sourceCreatedByName: actorName, collectorUid: f.rep, collectorName: actorName} : {})});
    batch.update(f.ref("cash_balances", `rep_${f.rep}`), {amount: Number(after) / 1000, lastMovementId: movementId, updatedAt: FieldValue.serverTimestamp()});
    await batch.commit();balanceUnits = after;
  }
  const current = await f.settle("selected-volume", 1.234);
  return {...f, count, currentId: current.settlementId, beforeUnits: balanceUnits.toString(), remainingUnits: (balanceUnits - 1234n).toString()};
}
async function receiptHistoryFixture(db, count) {
  const f = await breakdownFixture(db);await f.invoice("dense-invoice");
  const receiptIds = Array.from({length: count}, (_, i) => `dense-${i.toString().padStart(6, "0")}`);
  await f.ref("invoices", "dense-invoice").update({receiptIds, paidAmount: count / 1000, remainingAmount: 30 - count / 1000});
  for (let start = 0; start < count; start += 200) {
    const batch = db.batch();
    for (let i = start; i < Math.min(start + 200, count); i++) {
      const id = receiptIds[i];batch.create(f.ref("receipts", id), {id, companyId: f.companyId, receiptNumber: `RC-${i}`, receiptDate: f.date,
        amount: 0.001, paymentMethod: "cash", customerId: "customer", cashMovementIds: [`${id}_cash`], invoiceAllocations: {"dense-invoice": 0.001},
        invoiceAllocationDetails: [{invoiceId: "dense-invoice", amount: 0.001}], createdByUid: f.rep, createdByName: f.rep, createdByRole: "sales_rep"});
    }
    await batch.commit();
  }
  let balance = 100111n;
  for (let i = 0; i < count; i++) {
    const id = receiptIds[i], batch = db.batch(), after = balance + 1n;
    batch.create(f.ref("cash_movements", `${id}_cash`), {id: `${id}_cash`, companyId: f.companyId, cashAccount: "rep_cash", salesRepId: f.rep,
      movementType: "receipt", type: "receipt_cash", direction: "in", amount: 0.001, balanceBefore: Number(balance) / 1000, balanceAfter: Number(after) / 1000,
      sourceCollection: "receipts", sourceId: id, sourceNumber: `RC-${i}`, referenceId: id, referenceNumber: `RC-${i}`, customerId: "customer", date: f.date, movementDate: f.date,
      createdByUid: f.rep, createdByName: f.rep, createdByRole: "sales_rep", createdAt: FieldValue.serverTimestamp()});
    batch.update(f.ref("cash_balances", `rep_${f.rep}`), {amount: Number(after) / 1000, lastMovementId: `${id}_cash`, updatedAt: FieldValue.serverTimestamp()});
    await batch.commit();balance = after;
  }
  const current = await f.settle("dense-receipts", 1.234);
  return {...f, currentId: current.settlementId, remainingUnits: (balance - 1234n).toString()};
}
module.exports = {volumeFixture, receiptHistoryFixture};
