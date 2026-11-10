"use strict";
// Pure synthetic DTO fixtures using the existing backend validator/page builder.
// No Firebase app, emulator, credentials, network or financial write is used.
const {writeFileSync} = require("node:fs");
const {join} = require("node:path");
const {analyzeSettlementSourceEvidence: analyze} = require("../../functions/lib/trusted/settlement_source_evidence");
const {settlementBreakdownDetailPage: page} = require("../../functions/lib/trusted/settlement_breakdown_presentation");
const {settlementInventoryEvidenceDigest: digest} = require("../../functions/lib/trusted/settlement_pending_evidence");
const companyId = "synthetic-phase2b11", salesRepId = "synthetic-representative", admin = "synthetic-administrator", c = `companies/${companyId}`;
const date = {seconds: 1794182400, nanoseconds: 123456000};
const name = "أحمد عبد الرحمن — Ahmed Abdulrahman";
const documents = [];let sequence = 0, rep = 0n, company = 0n;
const stamp = () => ({seconds: 1794182400 + ++sequence, nanoseconds: 123456000});
const doc = (collection, id, data, clock = stamp()) => {
  const d = {id, path: `${c}/${collection}/${id}`, data: {id, companyId, createdByUid: admin, createdByName: "مدير الحسابات / Finance administrator", createdByRole: "admin", ...data}, createTime: clock, updateTime: clock};documents.push(d);return d;
};
const movement = (id, amount, direction, collection, sourceId, sourceNumber, extra = {}, clock = stamp()) => {
  const account = extra.cashAccount || "rep_cash", before = account === "rep_cash" ? rep : company, signed = direction === "in" ? amount : -amount, after = before + signed;
  if (account === "rep_cash") rep = after;else company = after;
  return doc("cash_movements", id, {cashAccount: account, salesRepId: account === "rep_cash" ? salesRepId : "", amount: Number(amount) / 1000, direction,
    balanceBefore: Number(before) / 1000, balanceAfter: Number(after) / 1000, date, movementDate: date, createdAt: clock, sourceCollection: collection, sourceId, referenceId: sourceId,
    sourceNumber, referenceNumber: sourceNumber, customerId: "synthetic-customer", ...extra}, clock);
};
movement("rep-opening", 100000n, "in", "cash_movements", "rep-opening", "OPEN-2026", {movementType: "opening_balance", type: "opening_balance", immutable: true});
movement("company-opening", 50000n, "in", "cash_movements", "company-opening", "OPEN-CO-2026", {cashAccount: "company_cash", movementType: "opening_balance", type: "opening_balance", immutable: true});
function invoice(id, units, seller = salesRepId) {
  doc("invoices", id, {invoiceNumber: `INV-${id}`, invoiceDate: date, financialPosted: true, invoiceStatus: "confirmed", initialPaidAmount: Number(units) / 1000,
    grandTotal: 30, initialCashAccount: "rep_cash", paymentType: units === 30000n ? "cash" : "partial", cashMovementIds: units > 0n ? [`${id}_cash`] : [],
    receiptIds: id === "credit" ? ["receipt"] : [], returnInvoiceIds: id === "cash" ? ["return"] : [], customerId: "synthetic-customer", salesRepId: seller, salesRepName: seller === salesRepId ? name : "البائع الأصلي / Original seller",
    createdByUid: seller, createdByName: name, createdByRole: "sales_rep", financialPostedByUid: admin, financialPostedByName: "مدير الحسابات"});
  if (units) movement(`${id}_cash`, units, "in", "invoices", id, `INV-${id}`, {movementType: "invoice_payment", type: units === 30000n ? "invoice_cash" : "invoice_partial", paymentType: units === 30000n ? "cash" : "partial", createdByUid: seller, createdByName: name, createdByRole: "sales_rep"});
}
invoice("cash", 30000n);invoice("credit", 0n, "synthetic-original-seller");
doc("receipts", "receipt", {receiptNumber: "RC-2026-007", receiptDate: date, amount: 5, paymentMethod: "cash", customerId: "synthetic-customer", cashMovementIds: ["receipt_cash"],
  invoiceAllocations: {credit: 5}, invoiceAllocationDetails: [{invoiceId: "credit", amount: 5}], createdByUid: salesRepId, createdByName: name, createdByRole: "sales_rep"});
movement("receipt_cash", 5000n, "in", "receipts", "receipt", "RC-2026-007", {movementType: "receipt", type: "receipt_cash", createdByUid: salesRepId, createdByName: name, createdByRole: "sales_rep"});
doc("sales_returns", "return", {returnNumber: "RET-2026-002", returnDate: date, originalInvoiceId: "cash", status: "confirmed", financialPosted: true, refundType: "cash_refund", cashRefundAmount: 2,
  grandTotal: 2, cashMovementIds: ["return_cash"], customerId: "synthetic-customer"});
movement("return_cash", 2000n, "out", "sales_returns", "return", "RET-2026-002", {movementType: "sales_return", type: "sales_return_cash_refund", originalCollectionSourceIds: ["cash_cash"]});
doc("expenses", "expense", {expenseDate: date, amount: 3.125, paymentMethod: "cash", fundingSource: "rep_collected_cash", status: "approved", cashMovementId: "expense_cash", salesRepId,
  createdByUid: salesRepId, createdByName: name, createdByRole: "sales_rep", approvedByUid: admin, approvedByName: "مدير الحسابات"});
movement("expense_cash", 3125n, "out", "expenses", "expense", "expense", {movementType: "expense", type: "expense_cash"});
function settle(id, amount) {
  const clock = stamp(), binding = {postedByUid: admin, postedByName: "مدير الحسابات", postedByRole: "admin", sourceCreatedByUid: admin};
  doc("settlements", id, {settlementNumber: id === "current" ? "SET-2026-011" : "SET-2026-010", settlementDate: date, amount: Number(amount) / 1000, status: "posted", salesRepId,
    repMovementId: `${id}_rep_out`, companyMovementId: `${id}_company_in`, sourceCashAccount: "rep_cash", sourceCashAccountId: `rep_${salesRepId}`, destinationCashAccount: "company_cash", destinationCashAccountId: "company_cash", ...binding}, clock);
  const number = id === "current" ? "SET-2026-011" : "SET-2026-010";
  movement(`${id}_rep_out`, amount, "out", "settlements", id, number, {movementType: "settlement_to_admin", type: "settlement_to_admin", counterpartMovementId: `${id}_company_in`, ...binding}, clock);
  movement(`${id}_company_in`, amount, "in", "settlements", id, number, {cashAccount: "company_cash", movementType: "settlement_to_admin", type: "settlement_to_admin", counterpartMovementId: `${id}_rep_out`, ...binding}, clock);
  return clock;
}
settle("previous", 20000n);for (let i = 0; i < 65; i++) invoice(`partial-${i}`, 1n);
const cutoff = settle("current", 10000n);
const balances = ["rep_cash", "company_cash"].map(account => {
  const head = documents.filter(d => d.path.includes("/cash_movements/") && d.data.cashAccount === account).at(-1), id = account === "rep_cash" ? `rep_${salesRepId}` : "company_cash";
  return {id, path: `${c}/cash_balances/${id}`, createTime: head.createTime, updateTime: head.createTime, data: {id, companyId, cashAccount: account, salesRepId: account === "rep_cash" ? salesRepId : "", amount: head.data.balanceAfter, lastMovementId: head.id, updatedAt: head.data.createdAt}};
});
function bundle(blocked) {
  const result = analyze({companyId, salesRepId, cutoff, settlementId: "current", currency: "JOD", documents: blocked ? documents.filter(d => d.id !== "rep-opening") : documents,
    balances, legacyCurrencyBound: true, validationProfile: "paged_v1"});
  if (result.status !== (blocked ? "blocked" : "verified_cash_reconstruction")) throw new Error(JSON.stringify(result.issues));
  const report = {...result, companyId, salesRepId, settlementId: "current", currency: "JOD", moneyScale: 3, cutoff: {basis: "sdk_commit_order", inclusiveThrough: cutoff},
    evidenceDigest: digest({synthetic: true, result}), snapshotCoverage: {complete: true, digest: digest({synthetic: true, blocked, cutoff})}};
  const pages = Array.from({length: Math.ceil(result.cutoffMovementIds.length / 64)}, (_, pageIndex) => page(report, {evidenceDigest: report.evidenceDigest, snapshotDigest: report.snapshotCoverage.digest, pageIndex}));
  return {fixture: "phase2b11-synthetic", representativeLabel: name, settlementLabel: "SET-2026-011", pages};
}
const fixture = {verified: bundle(false), blocked: bundle(true), incomplete: {fixture: "phase2b11-synthetic", representativeLabel: name, settlementLabel: "SET-2026-011",
  notice: {companyId, salesRepId, settlementId: "current", state: "incomplete_coverage", reason: "inventory_bound_exceeded"}}};
writeFileSync(join(__dirname, "../fixtures/settlement_details.json"), JSON.stringify(fixture, null, 2));
console.log(JSON.stringify({pages: fixture.verified.pages.length, rows: fixture.verified.pages[0].rowCount, totals: fixture.verified.pages[0].totals}));
