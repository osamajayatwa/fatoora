"use strict";
const assert = require("node:assert/strict");
const {test, after} = require("node:test");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw new Error("Settlement breakdown tests require isolated loopback emulators.");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {settlementBreakdownTransaction: breakdown} = require("../lib/trusted/settlement_breakdown");
const {analyzeCashRecords} = require("../scripts/cash_reconciliation_common");
const {reassignCustomerTransaction} = require("../lib/trusted/customer_assignment");
const {breakdownFixture, time} = require("./helpers/settlement_breakdown_fixture");
const app = initializeApp({projectId: "demo-fatoora-phase2b7"}, "settlement-breakdown-tests"), db = getFirestore(app);
after(() => deleteApp(app));
const fixture = options => breakdownFixture(db, options);
const assertVerified = r => assert.equal(r.status, "verified_cash_reconstruction", JSON.stringify(r.issues));
const assertBlocked = (r, code) => {assert.equal(r.status, "blocked");assert.equal(r.totals, null);if (code) assert.ok(r.issues.some(i => i.code === code), JSON.stringify(r.issues));};
const errorCode = code => e => {assert.equal(e.code, code, e.stack);return true;};
async function snapshot(f) {
  const rows = [];
  for (const collection of ["cash_movements", "cash_balances", "invoices", "receipts", "sales_returns", "expenses", "settlements", "financial_ledger_entries"])
    for (const doc of (await db.collection(`${f.c}/${collection}`).get()).docs) rows.push({path: doc.ref.path, data: doc.data(), version: time(doc.updateTime)});
  return rows.sort((a, b) => a.path.localeCompare(b.path));
}
function wrapped(run, extra = {}) {return new Proxy(db, {get(target, prop) {
  if (Object.hasOwn(extra, prop)) return extra[prop];if (prop === "runTransaction") return (callback, options) => run(callback, options);
  const value = Reflect.get(target, prop, target);return typeof value === "function" ? value.bind(target) : value;
}});}
function proxyTx(tx, extra) {return new Proxy(tx, {get(target, prop) {const value = extra[prop] || Reflect.get(target, prop, target);return typeof value === "function" ? value.bind(target) : value;}});}

test("actual workflows reconstruct invoice/receipt/refund/expense/repeated settlements and exact carry without allocations or writes", async t => {
  const f = await fixture();await f.invoice("invoice-a", {paid: 10});await f.invoice("invoice-b");
  const receipt = await f.receipt("multi", 25);await f.refund("return-a", "invoice-a");await f.expense("paid", 3.125);
  const pending = await f.expense("pending", 4, "rep_collected_cash", false), personal = await f.expense("personal", 2, "personal_cash");
  const previous = await f.settle("previous", 20);await f.receipt("later", 2.009);const current = await f.settle("current", 5.111);
  const before = await snapshot(f), r = await f.breakdown(current.settlementId);assertVerified(r);
  assert.deepEqual(r.totals, {openingUnits: "100111", carryUnits: "101986", activitySinceCarryUnits: "2009", cashAvailableBeforeUnits: "103995", transferredUnits: "5111", remainingUnits: "98884", currentBalanceUnits: "98884"});
  assert.equal(r.carry.previousSettlementId, previous.settlementId);assert.equal(r.movements.filter(m => m.source.id === receipt.receiptId).length, 1);
  const collection = r.movements.find(m => m.source.id === receipt.receiptId);
  assert.deepEqual(collection.receivableAllocations, [{invoiceId: "invoice-a", amountUnits: "20000"}, {invoiceId: "invoice-b", amountUnits: "5000"}]);
  assert.equal(collection.amountUnits, "25000");assert.equal(collection.unallocatedReceiptUnits, "0");
  assert.ok(r.nonCashSources.expenses.some(s => s.id === pending.expenseId));assert.ok(r.nonCashSources.expenses.some(s => s.id === personal.expenseId));
  assert.equal(r.allocation.settlementSourceAllocations, null);assert.equal(r.allocation.receivableAllocationsAreSettlementAllocations, false);
  const movements = (await db.collection(`${f.c}/cash_movements`).get()).docs.map(s => ({id: s.id, data: s.data()}));
  const storedBalances = (await db.collection(`${f.c}/cash_balances`).get()).docs.map(s => ({id: s.id, data: s.data()}));
  const legacy = analyzeCashRecords({companyId: f.companyId, movements, storedBalances});assert.equal(legacy.issueCount, 0);
  assert.equal(legacy.accounts.find(a => a.salesRepId === f.rep).calculatedBalance, 98.884);
  assert.deepEqual(await snapshot(f), before);assert.ok(Object.isFrozen(r));
  t.diagnostic(`Base lifecycle: ${r.observation.documentGets} document gets, ${r.observation.queryCount} queries, ${r.observation.scannedDocuments} scanned rows, zero writes.`);
});

test("refund after settlement reduces only current paying cash; historical transferred/remaining results and settlement remain immutable", async () => {
  const f = await fixture();await f.invoice("paid", {paid: 30});const settlement = await f.settle("before-refund", 10);
  const before = await f.breakdown(settlement.settlementId);assertVerified(before);const original = await f.ref("settlements", settlement.settlementId).get();
  await f.refund("after-refund", "paid");const after = await f.breakdown(settlement.settlementId);assertVerified(after);
  assert.equal(before.totals.remainingUnits, "120111");assert.equal(after.totals.remainingUnits, "120111");assert.equal(after.totals.currentBalanceUnits, "110111");
  assert.deepEqual((await f.ref("settlements", settlement.settlementId).get()).data(), original.data());
  const refund = after.movements.find(m => m.category === "cash_refund");assert.equal(refund.holderUid, f.rep);assert.equal(refund.signedUnits, "-10000");
  assert.ok(!after.cutoffMovementIds.includes(refund.id));
});

test("company cash may carry the representative's seller ID and is excluded from representative availability", async () => {
  const f = await fixture();await f.invoice("company-sale", {actor: f.admin, seller: f.rep, paid: 30});await f.refund("company-refund", "company-sale");
  const settlement = await f.settle("company-scope", 1), r = await f.breakdown(settlement.settlementId);assertVerified(r);
  assert.equal(r.totals.cashAvailableBeforeUnits, "100111");
  const companySale = r.excludedMovements.find(m => m.category === "invoice_collection");assert.equal(companySale.holderUid, f.companyId);assert.equal(companySale.recordedSalesRepId, f.rep);
  assert.equal(companySale.originalSellers[0].uid, f.rep);assert.ok(r.excludedMovements.some(m => m.category === "cash_refund" && m.holderUid === f.companyId));
});

test("customer-credit/debt reduction returns and bank receipts never create representative cash", async () => {
  const f = await fixture();await f.invoice("credit-sale");const bank = await f.receipt("bank", 5, f.rep, "bank");await f.refund("credit-return", "credit-sale", 1, "credit_customer_balance");
  const settlement = await f.settle("noncash", 1), r = await f.breakdown(settlement.settlementId);assertVerified(r);
  assert.equal(r.totals.cashAvailableBeforeUnits, "100111");assert.ok(r.nonCashSources.receipts.some(s => s.id === bank.receiptId));assert.ok(r.nonCashSources.sales_returns.some(s => s.id === "credit-return"));
});

test("negative cash on a credit-only return is inconsistent evidence rather than a zero cash effect", async () => {
  const f = await fixture();await f.invoice("negative-return");await f.refund("credit-only", "negative-return", 1, "credit_customer_balance");
  await f.ref("sales_returns", "credit-only").update({cashRefundAmount: -1});assertBlocked(await f.preview(), "inconsistent_source");
});

test("an exact stored string zero remains a non-cash invoice rather than an invented unresolved collection", async () => {
  const f = await fixture();await f.invoice("string-zero");await f.ref("invoices", "string-zero").update({initialPaidAmount: "0"});const r = await f.preview();assertVerified(r);
  assert.ok(r.nonCashSources.invoices.some(i => i.id === "string-zero"));assert.deepEqual(r.unresolvedSources.invoices, []);
});

test("receipt cancellation counts original IN and one reciprocal OUT once", async () => {
  const f = await fixture();await f.invoice("cancel-sale");const receipt = await f.receipt("cancel", 10);await f.cancel(receipt.receiptId);
  const current = await f.settle("after-cancel", 1), r = await f.breakdown(current.settlementId);assertVerified(r);
  assert.equal(r.totals.cashAvailableBeforeUnits, "100111");const legs = r.movements.filter(m => m.source.id === receipt.receiptId);assert.equal(legs.length, 2);
  assert.equal(legs.reduce((sum, m) => sum + BigInt(m.signedUnits), 0n), 0n);assert.equal(legs[1].reversesMovementId, legs[0].id);
});

test("cancellation after cash settlement remains blocked by existing workflow and creates no reversal", async () => {
  const f = await fixture();await f.invoice("cancel-used");const receipt = await f.receipt("used", 10);const current = await f.settle("uses-receipt", 1);
  const before = await snapshot(f);await assert.rejects(f.cancel(receipt.receiptId));assert.deepEqual(await snapshot(f), before);assertVerified(await f.breakdown(current.settlementId));
});

test("reassigned receipt collector stays distinct from original invoice seller and mixed original holders block cash refund", async () => {
  const f = await fixture();await f.invoice("old-seller", {paid: 10});
  await reassignCustomerTransaction(db, f.admin, {companyId: f.companyId, customerId: "customer", assignedToUid: f.other,
    expectedAssignedToUid: f.rep, expectedAssignmentRevision: 0, reason: "Synthetic", idempotencyKey: "reassignment-key"});
  const receipt = await f.receipt("new-collector", 20, f.other);await assert.rejects(f.refund("mixed-holders", "old-seller"));
  const current = await f.settle("seller-only", 1), r = await f.breakdown(current.settlementId);assertVerified(r);
  assert.equal(r.totals.cashAvailableBeforeUnits, "110111");const other = r.excludedMovements.find(m => m.source.id === receipt.receiptId);
  assert.equal(other.holderUid, f.other);assert.equal(other.collector.uid, f.other);assert.equal(other.originalSellers[0].uid, f.rep);
});

test("commit ordering controls reconstruction even when business dates are reversed", async () => {
  const f = await fixture();await f.invoice("later-business", {paid: 10, businessDate: Timestamp.fromDate(new Date("2026-12-01"))});
  await f.invoice("earlier-business", {paid: 5, businessDate: Timestamp.fromDate(new Date("2026-01-01"))});const current = await f.settle("date-order", 1);
  const r = await f.breakdown(current.settlementId);assertVerified(r);assert.equal(r.totals.cashAvailableBeforeUnits, "115111");
  assert.ok(r.committedOrder.indexOf("later-business_cash") < r.committedOrder.indexOf("earlier-business_cash"));
  assert.ok(r.businessDatePresentationOrder.indexOf("earlier-business_cash") < r.businessDatePresentationOrder.indexOf("later-business_cash"));
});

test("missing opening is unknown even with an observed zero before balance", async () => {
  const f = await fixture({opening: false});await f.ref("cash_balances", `rep_${f.rep}`).update({amount: 0});
  await f.invoice("zero-start", {paid: 10});const current = await f.settle("unknown-origin", 1), r = await f.breakdown(current.settlementId);
  assertBlocked(r, "unknown_opening");assert.equal(r.opening.amountUnits, null);assert.equal(r.carry.amountUnits, null);assert.equal(r.coverage.unknownOpeningAssumedZero, false);
});

test("preview uses a past SDK cutoff and never assumes an origin before the recorded opening", async () => {
  const f = await fixture();const r = await f.preview();assertVerified(r);assert.equal(r.totals.transferredUnits, "0");assert.equal(r.totals.remainingUnits, "100111");
  assertBlocked(await f.preview({committedThrough: {seconds: 0, nanoseconds: 0}}), "unknown_opening");
});

test("mill precision reconciles fractional invoice/receipt collections and full refund exactly", async () => {
  const f = await fixture();await f.invoice("mill-sale", {quantity: 1, price: 0.003, paid: 0.001});await f.receipt("mill", 0.002);
  await f.refund("mill-refund", "mill-sale");const current = await f.settle("mill", 0.001), r = await f.breakdown(current.settlementId);assertVerified(r);
  assert.equal(r.observedCategoryNetUnits.invoice_collection, "1");assert.equal(r.observedCategoryNetUnits.receipt_collection, "2");assert.equal(r.observedCategoryNetUnits.cash_refund, "-3");
  assert.equal(r.totals.cashAvailableBeforeUnits, "100111");assert.equal(r.totals.remainingUnits, "100110");
});

test("receipt against a customer opening balance stays explicitly unallocated to invoices", async () => {
  const f = await fixture();await f.ref("customers", "customer").update({currentBalance: 10});const receipt = await f.receipt("unallocated-customer", 7.111);
  const current = await f.settle("unallocated", 1), r = await f.breakdown(current.settlementId);assertVerified(r);
  const row = r.movements.find(m => m.source.id === receipt.receiptId);assert.deepEqual(row.receivableAllocations, []);assert.deepEqual(row.originalSellers, []);
  assert.equal(row.unallocatedReceiptUnits, "7111");assert.equal(r.totals.remainingUnits, "106222");assert.equal(r.allocation.settlementSourceAllocations, null);
});

test("partial-payment returns reduce debt before a paid-portion cash refund", async () => {
  const f = await fixture();await f.invoice("partial-return", {paid: 10});await f.refund("debt-first", "partial-return", 1);
  await f.refund("paid-next", "partial-return", 2);const current = await f.settle("debt-vs-cash", 1), r = await f.breakdown(current.settlementId);assertVerified(r);
  assert.equal(r.movements.filter(m => m.category === "cash_refund").length, 1);assert.equal(r.totals.cashAvailableBeforeUnits, "100111");
  assert.ok(r.nonCashSources.sales_returns.some(s => s.id === "debt-first"));
});

test("refund after a full settlement cannot debit company cash to cover an empty original representative account", async () => {
  const f = await fixture();await f.invoice("fully-settled", {paid: 30});const current = await f.settle("all-cash", 130.111), before = await snapshot(f);
  await assert.rejects(f.refund("insufficient-rep", "fully-settled"));assert.deepEqual(await snapshot(f), before);
  const r = await f.breakdown(current.settlementId);assertVerified(r);assert.equal(r.totals.remainingUnits, "0");
  const preview = await f.preview();assertVerified(preview);assert.equal(preview.carry.amountUnits, "0");assert.equal(preview.totals.cashAvailableBeforeUnits, "0");
});

test("unknown nonzero opening makes subsequent settlement carry unverifiable rather than inventing a source lot", async () => {
  const f = await fixture({opening: false}), previous = await f.settle("unknown-previous", 20), current = await f.settle("unknown-current", 5);
  const r = await f.breakdown(current.settlementId);assertBlocked(r, "unknown_opening");assert.equal(r.carry.previousSettlementId, previous.settlementId);assert.equal(r.carry.amountUnits, null);
});

test("approved company expense does not reduce representative cash and its head preserves company custody", async () => {
  const f = await fixture(), current = await f.settle("company-expense", 1);await f.expense("company-paid", 2, "company_cash", true, f.admin);
  const r = await f.breakdown(current.settlementId);assertVerified(r);assert.equal(r.totals.remainingUnits, "99111");
  const expense = r.excludedMovements.find(m => m.category === "cash_expense");assert.equal(expense.holderUid, f.companyId);assert.equal(expense.sourceCreator.uid, f.admin);
});

test("a current company-cash head may retain a seller representative without changing its cash holder", async () => {
  const f = await fixture(), current = await f.settle("company-head", 1);await f.invoice("latest-company-head", {actor: f.admin, seller: f.rep, paid: 30});
  const r = await f.breakdown(current.settlementId);assertVerified(r);assert.equal(r.totals.remainingUnits, "99111");
  const head = r.excludedMovements.find(m => m.id === "latest-company-head_cash");assert.equal(head.holderUid, f.companyId);assert.equal(head.recordedSalesRepId, f.rep);
});

test("provenance keeps representative expense creator separate from approving administrator", async () => {
  const f = await fixture(), expense = await f.expense("actor-evidence", 1), current = await f.settle("actors", 1), r = await f.breakdown(current.settlementId);assertVerified(r);
  const row = r.movements.find(m => m.source.id === expense.expenseId);assert.equal(row.sourceCreator.uid, f.rep);assert.equal(row.movementCreator.uid, f.admin);assert.equal(row.postingActor.uid, f.admin);
});

test("an unsupported cash adjustment with valid balances still cannot become a verified contribution", async () => {
  const f = await fixture(), id = "manual-adjustment", batch = db.batch();
  batch.create(f.ref("cash_movements", id), {id, companyId: f.companyId, cashAccount: "rep_cash", salesRepId: f.rep, movementType: "manual_adjustment", type: "manual_adjustment",
    direction: "in", amount: 1, balanceBefore: 100.111, balanceAfter: 101.111, date: f.date, movementDate: f.date, sourceCollection: "cash_movements", sourceId: id, referenceId: id,
    createdByUid: f.admin, createdByName: f.admin, createdByRole: "admin", createdAt: FieldValue.serverTimestamp()});
  batch.update(f.ref("cash_balances", `rep_${f.rep}`), {amount: 101.111, lastMovementId: id, updatedAt: FieldValue.serverTimestamp()});await batch.commit();
  assertBlocked(await f.preview(), "unsupported_adjustment");
});

test("a missing movement and its deleted source still leave a detectable committed cash-chain gap", async () => {
  const f = await fixture();await f.invoice("deleted-source", {paid: 10});await f.invoice("following-source", {paid: 5});const current = await f.settle("chain-gap", 1);
  await f.ref("cash_movements", "deleted-source_cash").delete();await f.ref("invoices", "deleted-source").delete();assertBlocked(await f.breakdown(current.settlementId), "incomplete_movement_coverage");
});

test("legacy movements cannot borrow a settlement-only currency binding", async () => {
  const f = await fixture({legacyCurrency: false});const batch = db.batch();batch.update(db.doc(f.b), {cashEvidenceCurrencyBindingId: "settlement-only"});
  batch.create(db.doc(`${f.b}/currency_bindings/settlement-only`), {id: "settlement-only", revisionId: "settlement-only", companyId: f.companyId, bookId: f.bookId,
    approvalStatus: "approved", currency: "JOD", moneyScale: 3, sourceCollection: "settlements", scope: "company_cash_ledger"});await batch.commit();
  assertBlocked(await f.preview(), "invalid_cash_currency_binding");
});

test("a newly created currency binding cannot retroactively attest earlier legacy cash", async () => {
  const f = await fixture({legacyCurrency: false});const batch = db.batch();batch.update(db.doc(f.b), {cashEvidenceCurrencyBindingId: "late-binding"});
  batch.create(db.doc(`${f.b}/currency_bindings/late-binding`), {id: "late-binding", revisionId: "late-binding", companyId: f.companyId, bookId: f.bookId,
    approvalStatus: "approved", currency: "JOD", moneyScale: 3, sourceCollection: "cash_movements", scope: "company_cash_ledger"});await batch.commit();
  assertBlocked(await f.preview(), "late_currency_binding");
});

for (const [label, mutate, code] of [
  ["unknown currency", async f => db.doc(f.b).update({cashEvidenceCurrencyBindingId: FieldValue.delete()}), "unknown_currency"],
  ["wrong binding scope", async f => db.doc(`${f.b}/currency_bindings/cash-ledger-v1`).update({sourceCollection: "settlements"}), "invalid_cash_currency_binding"],
  ["current balance", async f => f.ref("cash_balances", `rep_${f.rep}`).update({amount: 0}), "inconsistent_source"],
  ["missing head", async f => f.ref("cash_balances", `rep_${f.rep}`).update({lastMovementId: "missing-head"}), "missing_cash_head"],
  ["missing opening", async f => f.ref("cash_movements", `rep_${f.rep}_opening`).delete(), "unknown_opening"],
  ["rewritten settlement", async (f, current) => f.ref("settlements", current).update({notes: "changed"}), "overwritten_evidence"],
  ["rewritten movement", async (f, current) => f.ref("cash_movements", `${current}_rep_out`).update({amount: 0.0001}), "overwritten_evidence"],
  ["missing settlement leg", async (f, current) => f.ref("cash_movements", `${current}_company_in`).delete(), "missing_movement"],
  ["active reconciliation", async f => f.ref("maintenance_locks", "cash_reconciliation").set({active: true}), "reconciliation_in_progress"],
]) test(`corrupt evidence: ${label} blocks totals without repair`, async () => {
  const f = await fixture(), current = await f.settle("corruption", 1);await mutate(f, current.settlementId);const before = await snapshot(f);
  assertBlocked(await f.breakdown(current.settlementId), code);assert.deepEqual(await snapshot(f), before);
});

for (const [label, patch] of [["receipt amount", {amount: 11}], ["cross-customer invoice", {customerId: "other-customer"}],
  ["duplicate cash reference", {cashMovementIds: ["missing", "missing"]}], ["allocation mismatch", {invoiceAllocationDetails: []}],
  ["inexact amount", {amount: 10.0001}], ["wrong business date", {receiptDate: Timestamp.fromMillis(1)}],
  ["wrong currency", {currency: "USD"}], ["oversized reference list", {cashMovementIds: Array.from({length: 33}, (_, i) => `ref-${i}`)}]]) test(`inconsistent source: ${label} is rejected independently of movement metadata`, async () => {
  const f = await fixture();await f.invoice("source-sale");const receipt = await f.receipt("source-probe", 10), current = await f.settle("source-probe", 1);
  await f.ref("receipts", receipt.receiptId).update(patch);assertBlocked(await f.breakdown(current.settlementId));
});

test("duplicate logical movements at alternate IDs block reconstruction", async () => {
  const f = await fixture();await f.invoice("dup-sale", {paid: 10});const current = await f.settle("dup-check", 1);
  const row = (await f.ref("cash_movements", "dup-sale_cash").get()).data();await f.ref("cash_movements", "duplicate-cash").create({...row, id: "duplicate-cash", createdAt: FieldValue.serverTimestamp()});
  assertBlocked(await f.breakdown(current.settlementId), "duplicate_movement");
});

test("an unsupported reversal cannot be counted as another original invoice collection", async () => {
  const f = await fixture();await f.invoice("reversal-source", {paid: 10});const row = (await f.ref("cash_movements", "reversal-source_cash").get()).data();
  await f.ref("cash_movements", "unsupported-reversal").create({...row, id: "unsupported-reversal", isReversal: true, reversesMovementId: row.id, createdAt: FieldValue.serverTimestamp()});
  assertBlocked(await f.preview(), "unsupported_adjustment");
});

test("source-side inventory detects a deleted declared movement", async () => {
  const f = await fixture();await f.invoice("hidden-sale", {paid: 10});const current = await f.settle("hidden-gap", 1);
  await f.ref("cash_movements", "hidden-sale_cash").delete();const r = await f.breakdown(current.settlementId);assertBlocked(r, "missing_movement");
  assert.ok(r.unresolvedSources.invoices.some(s => s.id === "hidden-sale"));assert.ok(!r.nonCashSources.invoices.some(s => s.id === "hidden-sale"));
});

test("read-only SDK, write traps, repeat digests, and concurrent reads/cash activity preserve deterministic cutoff results", async () => {
  const f = await fixture(), current = await f.settle("concurrent", 1);let writes = 0;
  const database = wrapped((callback, options) => {assert.deepEqual(options, {readOnly: true});return db.runTransaction(tx => callback(proxyTx(tx,
    Object.fromEntries(["set", "create", "update", "delete"].map(k => [k, () => {writes++;throw new Error("write");}])))), options);});
  const first = await f.breakdown(current.settlementId, {}, f.admin, database), second = await f.breakdown(current.settlementId);assertVerified(first);assert.equal(first.evidenceDigest, second.evidenceDigest);
  const results = await Promise.all([f.breakdown(current.settlementId), f.settle("later-concurrent", 2), f.breakdown(current.settlementId)]);
  for (const r of [results[0], results[2]]) {assertVerified(r);assert.equal(r.totals.cashAvailableBeforeUnits, "100111");assert.equal(r.totals.remainingUnits, "99111");}
  assert.equal(writes, 0);
});

test("bounded transport retries reauthorize; unrelated permission/invalid errors do not retry", async () => {
  const f = await fixture(), current = await f.settle("retry", 1);let attempts = 0;
  const database = wrapped(async (callback, options) => {if (++attempts === 1) throw Object.assign(new Error("aborted"), {code: 10});return db.runTransaction(callback, options);});
  assertVerified(await f.breakdown(current.settlementId, {}, f.admin, database));assert.equal(attempts, 3);
  for (const code of [10, 3, 7]) {attempts = 0;await assert.rejects(f.breakdown(current.settlementId, {}, f.admin,
    wrapped(async () => {attempts++;throw Object.assign(new Error("unrelated"), {code});})), errorCode(code));assert.equal(attempts, code === 10 ? 5 : 1);}
});

test("revocation between bounded retries denies access to all source evidence", async () => {
  const f = await fixture(), current = await f.settle("revocation", 1);let attempts = 0;
  const database = wrapped(async (callback, options) => {if (++attempts === 1) {await db.doc(`users/${f.admin}`).update({active: false});throw Object.assign(new Error("retry"), {code: 10});}return db.runTransaction(callback, options);});
  await assert.rejects(f.breakdown(current.settlementId, {}, f.admin, database), errorCode("permission-denied"));assert.equal(attempts, 2);
});

test("request identity and cutoff are captured before asynchronous work", async () => {
  const f = await fixture(), current = await f.settle("captured", 1), request = {companyId: f.companyId, salesRepId: f.rep, settlementId: current.settlementId};
  const pending = breakdown(db, f.admin, request, {enableEmulatorBreakdown: true});request.salesRepId = f.other;request.settlementId = "changed-after-start";
  const r = await pending;assertVerified(r);assert.equal(r.salesRepId, f.rep);assert.equal(r.settlementId, current.settlementId);
});

test("oversized projected source payload rejects within a fixed read budget", async () => {
  const f = await fixture();await f.ref("receipts", "large-receipt").create({id: "large-receipt", companyId: f.companyId, paymentMethod: "bank", cashMovementIds: [], invoiceAllocations: {oversized: "x".repeat(70000)}});
  await assert.rejects(f.preview(), errorCode("resource-exhausted"));
});

test("configured inventory ceiling returns blocked incomplete coverage without clearing totals", async () => {
  const f = await fixture(), batch = db.batch();for (let index = 0; index < 65; index++) batch.create(f.ref("expenses", `pending-${index}`), {id: `pending-${index}`, companyId: f.companyId, status: "pending", fundingSource: "rep_collected_cash", cashMovementId: ""});
  await batch.commit();const observation = await db.doc(f.c).get();
  const r = await breakdown(db, f.admin, {companyId: f.companyId, salesRepId: f.rep, committedThrough: time(observation.readTime)}, {enableEmulatorBreakdown: true, readBudget: 64});
  assertBlocked(r, "inventory_bound_exceeded");assert.equal(r.coverage.inventory, "incomplete_bound_exceeded");assert.ok(r.observation.queryCount <= 256);
});

for (const [label, change] of [["inactive viewer", f => db.doc(`users/${f.admin}`).update({active: false})], ["unapproved viewer", f => db.doc(`users/${f.admin}`).update({approvalStatus: "pending"})],
  ["foreign viewer", f => db.doc(`users/${f.admin}`).update({companyId: "foreign"})], ["forged viewer", f => db.doc(`users/${f.admin}`).update({uid: "wrong-uid"})],
  ["foreign representative", f => db.doc(`users/${f.rep}`).update({companyId: "foreign"})], ["inactive company", f => db.doc(f.c).update({active: false})]]) test(`permission safety: ${label}`, async () => {
  const f = await fixture();await change(f);await assert.rejects(f.preview(), errorCode("permission-denied"));
});

test("unauthenticated/representative access, wrong project, disabled adapter, future/ambiguous cutoff and malformed IDs fail before evidence exposure", async () => {
  const f = await fixture();await assert.rejects(f.preview({}, ""), errorCode("unauthenticated"));await assert.rejects(f.preview({}, f.rep), errorCode("permission-denied"));
  const request = {companyId: f.companyId, salesRepId: f.rep, committedThrough: {seconds: 0, nanoseconds: 0}};
  await assert.rejects(breakdown(db, f.admin, request), /disabled by default/);
  await assert.rejects(breakdown(wrapped(async () => {throw new Error("must not read");}, {projectId: "production-project"}), f.admin, request, {enableEmulatorBreakdown: true}));
  await assert.rejects(f.preview({settlementId: "ambiguous"}), errorCode("invalid-argument"));
  await assert.rejects(f.preview({committedThrough: {seconds: 253402300799, nanoseconds: 0}}), errorCode("invalid-argument"));
  await assert.rejects(f.preview({salesRepId: "../foreign"}));
});

test("historical representative deactivation does not revoke today's administrator viewing authority", async () => {
  const f = await fixture(), current = await f.settle("inactive-rep", 1);await db.doc(`users/${f.rep}`).update({active: false});assertVerified(await f.breakdown(current.settlementId));
});

test("atomic settlement accounting envelopes are reused read-only; corrupt journal evidence blocks a balanced cash breakdown", async () => {
  const f = await fixture(), batch = db.batch(), scoped = id => ({id, companyId: f.companyId, bookId: f.bookId, revisionId: id, approvalStatus: "approved"});
  batch.update(db.doc(f.b), {revisionId: "book-v1", active: true, mode: "configuration", settlementPreflightEnabled: true,
    policyRevisionId: "policy-v1", settlementMappingRevisionId: "mapping-v1", settlementPeriodId: "period-v1",
    settlementJournalEmulatorEnabled: true, settlementJournalDefinitionId: "settlement-journal", settlementJournalDefinitionRevisionId: "journal-v1", postingLaneCount: 4, postingLaneSchemaVersion: 1});
  batch.create(db.doc(`${f.b}/policy_revisions/policy-v1`), {...scoped("policy-v1"), currency: "JOD", moneyScale: 3, accountingDateBasis: "settlement_business_date", legacyCurrencyBindingId: "settlement-v1"});
  batch.create(db.doc(`${f.b}/currency_bindings/settlement-v1`), {...scoped("settlement-v1"), currency: "JOD", moneyScale: 3, sourceCollection: "settlements", postingSource: "recordCashSettlement", settlementMetadataVersion: 1});
  batch.create(db.doc(`${f.b}/settlement_mappings/mapping-v1`), {...scoped("mapping-v1"), companyCashAccountId: "company-control", companyCashAccountRevisionId: "company-v1", representativeCashAccountId: "rep-control", representativeCashAccountRevisionId: "rep-v1"});
  for (const [id, revisionId] of [["company-control", "company-v1"], ["rep-control", "rep-v1"]]) batch.create(db.doc(`${f.b}/chart_accounts/${id}`), {...scoped(id), revisionId,
    currency: "JOD", moneyScale: 3, accountType: "asset", control: "cash", active: true, postingAllowed: true, requiresTreasuryDimension: true});
  batch.create(db.doc(`${f.b}/periods/period-v1`), {...scoped("period-v1"), status: "open", startsAt: Timestamp.fromDate(new Date("2026-01-01")), endsAt: Timestamp.fromDate(new Date("2027-01-01"))});
  batch.create(db.doc(`${f.b}/journal_definitions/settlement-journal`), {...scoped("settlement-journal"), revisionId: "journal-v1", active: true,
    action: "rep_to_company_cash", currency: "JOD", moneyScale: 3, numberingPolicy: "source_identity"});await batch.commit();
  const {pendingSettlementEvidenceTransaction} = require("../lib/trusted/settlement_pending_evidence"), {persistSettlementJournalTransaction} = require("../lib/trusted/settlement_journal_persistence");
  const input = {companyId: f.companyId, salesRepId: f.rep, idempotencyKey: "synthetic-atomic-breakdown", amount: "1.234", settlementDate: time(f.date), notes: "Synthetic"};
  const {evidence} = await pendingSettlementEvidenceTransaction(db, f.admin, input);
  const posted = await persistSettlementJournalTransaction(db, f.admin, input, evidence, {enableEmulatorPersistence: true});
  const before = await snapshot(f), r = await f.breakdown(posted.result.settlementId);assertVerified(r);assert.equal(r.accountingEvidence, "validated_atomic_envelope");
  assert.equal(r.totals.remainingUnits, "98877");assert.deepEqual(await snapshot(f), before);
  await db.doc(`${f.b}/journal_entries/${posted.result.journalId}`).update({syntheticCorruption: true});assertBlocked(await f.breakdown(posted.result.settlementId), "atomic_accounting_evidence");
});

test("phase boundaries: no root export, callable, posting/allocation/write integration", () => {
  assert.doesNotMatch(readFileSync(join(__dirname, "../src/index.ts"), "utf8"), /settlement_breakdown|settlement_source_evidence/);
  const adapter = readFileSync(join(__dirname, "../src/trusted/settlement_breakdown.ts"), "utf8");assert.doesNotMatch(adapter, /onCall|FieldValue|\.batch\(|persistSettlementJournalTransaction|prepareCashSettlementWrite/);
});
