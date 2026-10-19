"use strict";
const assert = require("node:assert/strict");
const {before, after, test} = require("node:test");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {createReceiptTransaction} = require("../lib/trusted/create_receipt");
const {cancelReceiptTransaction} = require("../lib/trusted/cancel_receipt");
const {recordCashSettlementTransaction} = require("../lib/trusted/record_cash_settlement");
const app = initializeApp({projectId: "fatoora-phase3-receipts-test"});
const db = getFirestore(app);
let sequence = 0;
before(() => assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Local emulator required"));
after(() => deleteApp(app));
async function fixture({collector = "admin", invoices = [100, 100], opening = 0} = {}) {
  const companyId = `cancellation-${++sequence}`;
  const path = (collection, id) => db.doc(`companies/${companyId}/${collection}/${id}`);
  const admin = `${companyId}-admin`;
  const rep = `${companyId}-rep`;
  for (const [uid, role] of [[admin, "admin"], [rep, "sales_rep"]]) {
    await db.doc(`users/${uid}`).set({uid, name: uid, role, companyId, active: true, approvalStatus: "approved"});
  }
  const balance = invoices.reduce((sum, amount) => sum + amount, opening);
  await path("customers", "customer").set({id: "customer", companyId, name: "Customer", createdByUid: rep,
    active: true, currentBalance: balance, totalSales: balance, totalPaid: 0});
  for (const [index, total] of invoices.entries()) {
    await path("invoices", `invoice-${index}`).set({id: `invoice-${index}`, companyId, customerId: "customer",
      invoiceNumber: `INV-${index}`, salesRepId: rep, salesRepName: rep, invoiceStatus: "confirmed", financialPosted: true,
      dueDate: Timestamp.fromMillis(1000 + index), invoiceDate: Timestamp.fromMillis(1000 + index),
      grandTotal: total, paidAmount: 0, remainingAmount: total, paymentStatus: "unpaid", receiptIds: [], hasReceivedPayment: false});
  }
  const post = async (amount, method = "cash", suffix = "first") => createReceiptTransaction(db,
    collector === "admin" ? admin : rep, companyId, `receipt-key-${suffix}`, {
      customerId: "customer", amount, paymentMethod: method, receiptDate: Date.now(), notes: "Original notes"});
  const cancel = (id, reason = "Entered in error", uid = admin) => cancelReceiptTransaction(db, uid, companyId, id, reason);
  const rows = async (name) => (await db.collection(`companies/${companyId}/${name}`).get()).docs.map((doc) => doc.data());
  return {companyId, path, admin, rep, post, cancel, rows};
}
async function state(f) {
  return Object.fromEntries(await Promise.all(["receipts", "customers", "invoices", "customer_transactions",
    "cash_movements", "cash_balances", "financial_ledger_entries"].map(async (name) => [name, await f.rows(name)])));
}
async function assertReversed(f, original, amount, initialBalance) {
  const receipt = (await f.path("receipts", original.receiptId).get()).data();
  assert.equal(receipt.status, "cancelled");
  assert.equal(receipt.cancelledByUid, f.admin);
  assert.equal(receipt.cancellationReason, "Entered in error");
  assert.ok(receipt.cancelledAt instanceof Timestamp);
  assert.equal(receipt.amount, amount);
  assert.equal(receipt.notes, "Original notes");
  const customer = (await f.path("customers", "customer").get()).data();
  assert.equal(customer.currentBalance, initialBalance);
  assert.equal(customer.totalPaid, 0);
  const transactions = await f.rows("customer_transactions");
  assert.equal(transactions.length, 2);
  assert.equal(transactions.reduce((sum, row) => sum + row.debitAmount - row.creditAmount, 0), 0);
  const entries = await f.rows("financial_ledger_entries");
  for (const metric of ["metricReceipts", "metricReceivables", "metricCompanyCashNet", "metricRepCashIn", "metricRepCashOut"]) {
    assert.equal(entries.reduce((sum, row) => sum + row[metric], 0), 0, metric);
  }
  for (const original of entries.filter((entry) => !entry.isReversal)) {
    const inverse = entries.find((entry) => entry.reversesEntryId === original.id);
    assert.equal(inverse.amount, original.amount);
    assert.equal(inverse.debitAccountKey, original.creditAccountKey);
    assert.equal(inverse.creditAccountKey, original.debitAccountKey);
  }
}

test("normal cash receipt cancellation appends inverse history and is idempotent", async () => {
  const f = await fixture();
  const posted = await f.post(100);
  const before = await state(f);
  assert.equal((await f.cancel(posted.receiptId)).alreadyCancelled, false);
  await assertReversed(f, posted, 100, 200);
  for (const name of ["customer_transactions", "cash_movements", "financial_ledger_entries"]) {
    const after = await f.rows(name);
    for (const original of before[name]) assert.deepEqual(after.find((row) => row.id === original.id), original);
  }
  assert.equal((await f.path("cash_balances", "company_cash").get()).data().amount, 0);
  const once = await state(f);
  assert.equal((await f.cancel(posted.receiptId, "Retry with a different reason")).alreadyCancelled, true);
  assert.deepEqual(await state(f), once);
});

test("multiple invoice and partial allocations restore only the original receipt amounts", async () => {
  const f = await fixture();
  await f.path("invoices", "invoice-1").update({salesRepId: "another-rep", salesRepName: "Another Rep"});
  const posted = await f.post(150, "bank");
  await f.cancel(posted.receiptId);
  await assertReversed(f, posted, 150, 200);
  for (const invoice of await f.rows("invoices")) {
    assert.equal(invoice.paidAmount, 0);
    assert.equal(invoice.remainingAmount, 100);
    assert.equal(invoice.paymentStatus, "unpaid");
    assert.deepEqual(invoice.receiptIds, []);
    assert.deepEqual(invoice.cancelledReceiptIds, [posted.receiptId]);
  }
  assert.equal((await f.rows("cash_movements")).length, 0);
  assert.equal((await f.rows("financial_ledger_entries")).filter((entry) => entry.isReversal).length, 2);
});

test("unallocated opening receivable and rep cash are restored to their original accounts", async () => {
  const f = await fixture({collector: "rep", invoices: [40], opening: 60});
  const posted = await f.post(70);
  assert.deepEqual((await f.path("receipts", posted.receiptId).get()).data().invoiceAllocations, {"invoice-0": 40});
  await f.cancel(posted.receiptId);
  await assertReversed(f, posted, 70, 100);
  assert.equal((await f.path("cash_balances", `rep_${f.rep}`).get()).data().amount, 0);
  assert.ok((await f.rows("cash_movements")).every((row) => row.cashAccount === "rep_cash" && row.salesRepId === f.rep));
});

test("unused legacy customer credit can be reversed; subsequent credit use is blocked atomically", async () => {
  for (const dependent of [false, true]) {
    const f = await fixture({invoices: [], opening: 100});
    const posted = await f.post(80, "bank");
    const receipt = (await f.path("receipts", posted.receiptId).get()).data();
    // Legacy overpayment evidence: a receipt of 80 against a balance of 30.
    await f.path("customer_transactions", receipt.customerTransactionIds[0]).update({balanceBefore: 30, balanceAfter: -50});
    await f.path("customers", "customer").update({currentBalance: dependent ? -40 : -50});
    if (dependent) await f.path("customer_transactions", "later-credit-use").set({id: "later-credit-use",
      customerId: "customer", createdAt: Timestamp.now(), debitAmount: 10, creditAmount: 0});
    const before = await state(f);
    if (dependent) {
      await assert.rejects(f.cancel(posted.receiptId), (error) => error.details?.dependency === "customer credit has subsequent transactions");
      assert.deepEqual(await state(f), before);
    } else {
      await f.cancel(posted.receiptId);
      await assertReversed(f, posted, 80, 30);
    }
  }
});

test("later receipts remain allocated when cancelling an earlier receipt", async () => {
  const f = await fixture({invoices: [100]});
  const first = await f.post(30, "bank");
  const second = await f.post(20, "bank", "second");
  await f.cancel(first.receiptId);
  const invoice = (await f.path("invoices", "invoice-0").get()).data();
  assert.equal(invoice.paidAmount, 20);
  assert.equal(invoice.remainingAmount, 80);
  assert.equal(invoice.paymentStatus, "partiallyPaid");
  assert.deepEqual(invoice.receiptIds, [second.receiptId]);
  assert.equal(invoice.lastReceiptId, second.receiptId);
});

test("initial invoice payments survive cancellation of a later partial receipt", async () => {
  const f = await fixture({invoices: [100]});
  await f.path("invoices", "invoice-0").update({paidAmount: 20, remainingAmount: 80, paymentStatus: "partiallyPaid", hasReceivedPayment: true});
  await f.path("customers", "customer").update({currentBalance: 80, totalPaid: 20});
  const posted = await f.post(30, "bank");
  await f.cancel(posted.receiptId);
  const invoice = (await f.path("invoices", "invoice-0").get()).data();
  assert.equal(invoice.paidAmount, 20);
  assert.equal(invoice.remainingAmount, 80);
  assert.equal(invoice.hasReceivedPayment, true);
  assert.equal(invoice.paymentStatus, "partiallyPaid");
  assert.equal((await f.path("customers", "customer").get()).data().totalPaid, 20);
});

test("check and CliQ reverse clearing entries without introducing cash movements", async () => {
  for (const method of ["check", "cliq"]) {
    const f = await fixture();
    const posted = await f.post(30, method);
    await f.cancel(posted.receiptId);
    await assertReversed(f, posted, 30, 200);
    assert.equal((await f.rows("cash_movements")).length, 0);
  }
});

test("unauthorized, cross-company, inactive, missing reason and unposted requests have no effects", async () => {
  const f = await fixture();
  const posted = await f.post(30);
  const foreign = "foreign-admin";
  await db.doc(`users/${foreign}`).set({uid: foreign, role: "admin", companyId: "another", active: true, approvalStatus: "approved"});
  const inactive = "inactive-admin";
  await db.doc(`users/${inactive}`).set({uid: inactive, role: "admin", companyId: f.companyId, active: false, approvalStatus: "approved"});
  const before = await state(f);
  for (const uid of [f.rep, foreign, inactive, undefined]) {
    await assert.rejects(cancelReceiptTransaction(db, uid, f.companyId, posted.receiptId, "Valid reason"),
      (error) => ["permission-denied", "unauthenticated"].includes(error.code));
  }
  for (const reason of ["", "  ", "x".repeat(501)]) await assert.rejects(f.cancel(posted.receiptId, reason), (error) => error.code === "invalid-argument");
  assert.deepEqual(await state(f), before);
  await f.path("receipts", posted.receiptId).update({status: "draft"});
  await assert.rejects(f.cancel(posted.receiptId), (error) => error.details?.dependency === "receipt is not posted");
});

test("sales returns and inconsistent original history reject without partial writes", async () => {
  for (const corrupt of ["return", "missing-ledger", "paid", "partial-reversal"]) {
    const f = await fixture();
    const posted = await f.post(30);
    if (corrupt === "return") await f.path("invoices", "invoice-0").update({returnedTotal: 1});
    if (corrupt === "paid") await f.path("invoices", "invoice-0").update({paidAmount: 0});
    if (corrupt === "missing-ledger") {
      for (const row of await f.rows("financial_ledger_entries")) await f.path("financial_ledger_entries", row.id).delete();
    }
    if (corrupt === "partial-reversal") {
      const {deterministicId} = require("../lib/trusted/common");
      await f.path("customer_transactions", deterministicId("receipt_cancel", posted.receiptId)).set({id: "conflicting"});
    }
    const before = await state(f);
    await assert.rejects(f.cancel(posted.receiptId), (error) => error.details?.reason === "receipt-cancellation-unsafe");
    assert.deepEqual(await state(f), before);
  }
});

test("settled rep cash blocks cancellation even when later collections replenish cash", async () => {
  const f = await fixture({collector: "rep"});
  const posted = await f.post(30);
  await recordCashSettlementTransaction(db, f.admin, f.companyId, "settlement-key", {salesRepId: f.rep, amount: 30, settlementDate: Date.now()});
  await f.post(50, "cash", "replenish");
  const before = await state(f);
  await assert.rejects(f.cancel(posted.receiptId), (error) => error.details?.dependency === "cash has subsequent spending or settlements");
  assert.deepEqual(await state(f), before);
});

async function transient(operation) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try { return await operation(); } catch (error) {
      if (!String(error.message).includes("Transaction is invalid or closed") || attempt === 2) throw error;
    }
  }
}
test("concurrent cancellation callers reverse once and retain the winning actor/reason", async () => {
  const f = await fixture();
  const posted = await f.post(70);
  const results = await Promise.all([transient(() => f.cancel(posted.receiptId)), transient(() => f.cancel(posted.receiptId))]);
  assert.deepEqual(results.map((result) => result.alreadyCancelled).sort(), [false, true]);
  await assertReversed(f, posted, 70, 200);
});
test("concurrent new receipt and cancellation serialize without losing allocations", async () => {
  const f = await fixture({invoices: [100]});
  const first = await f.post(30, "bank");
  await Promise.all([transient(() => f.cancel(first.receiptId)), transient(() => f.post(20, "bank", "concurrent"))]);
  const invoice = (await f.path("invoices", "invoice-0").get()).data();
  assert.equal(invoice.paidAmount, 20);
  assert.equal(invoice.remainingAmount, 80);
  assert.equal((await f.path("customers", "customer").get()).data().currentBalance, 80);
});
test("concurrent settlement and cancellation cannot both consume the original rep cash", async () => {
  const f = await fixture({collector: "rep"});
  const posted = await f.post(30);
  const results = await Promise.allSettled([transient(() => f.cancel(posted.receiptId)),
    transient(() => recordCashSettlementTransaction(db, f.admin, f.companyId, "concurrent-settle", {salesRepId: f.rep, amount: 30, settlementDate: Date.now()}))]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal((await f.path("cash_balances", `rep_${f.rep}`).get()).data().amount, 0);
  const receipt = (await f.path("receipts", posted.receiptId).get()).data();
  assert.equal((await f.path("customers", "customer").get()).data().currentBalance, receipt.status === "cancelled" ? 200 : 170);
});

test("callable authentication and existing rules prevent UI bypass and direct history changes", async () => {
  const {cancelReceipt} = require("../lib/trusted/cancel_receipt");
  await assert.rejects(cancelReceipt.run({data: {}}), (error) => error.code === "unauthenticated");
  const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
  const {readFileSync} = require("node:fs");
  const {join} = require("node:path");
  const {doc, updateDoc, deleteDoc, setDoc} = require("firebase/firestore");
  const environment = await initializeTestEnvironment({projectId: "fatoora-phase3-receipts-test",
    firestore: {rules: readFileSync(join(__dirname, "../../firestore.rules"), "utf8")}});
  try {
    const f = await fixture();
    const posted = await f.post(30);
    for (const uid of [f.admin, f.rep]) {
      const client = environment.authenticatedContext(uid).firestore();
      const clientRef = (name, id) => doc(client, `companies/${f.companyId}/${name}/${id}`);
      await assertFails(updateDoc(clientRef("receipts", posted.receiptId), {status: "cancelled"}));
      await assertFails(deleteDoc(clientRef("receipts", posted.receiptId)));
      for (const name of ["customer_transactions", "cash_movements", "financial_ledger_entries"]) {
        const original = (await f.rows(name))[0];
        await assertFails(updateDoc(clientRef(name, original.id), {amount: 0}));
        await assertFails(setDoc(clientRef(name, "fake-reversal"), {amount: 30}));
      }
    }
  } finally { await environment.cleanup(); }
});

test("dashboard totals, ledger projections and historical rebuild include cancellation correctly", async () => {
  const f = await fixture({collector: "rep", invoices: [], opening: 100});
  const posted = await f.post(30);
  await f.cancel(posted.receiptId);
  const {getDashboardSnapshot} = require("../lib/trusted/dashboard_reporting");
  const snapshot = await getDashboardSnapshot.run({auth: {uid: f.admin}, data: {companyId: f.companyId, from: 0, to: Date.now() + 1000}});
  assert.equal(snapshot.receiptCount, 0);
  // The reporting shape keeps period totals together.
  assert.ok(snapshot.salesByRepSummary.every((row) => row.receiptsCollected === 0));
  const {reconcileFinancialLedgerProjection, buildLedgerDerivedProjection} = require("../lib/trusted/financial_ledger_reporting");
  const {buildFinancialLedgerAccountActivity} = require("../lib/trusted/financial_ledger_account_reporting");
  const entries = await f.rows("financial_ledger_entries");
  for (const entry of entries) {
    assert.equal(buildLedgerDerivedProjection(entry.id, entry).metrics.metricReceipts, entry.metricReceipts);
    assert.ok(buildFinancialLedgerAccountActivity(entry.id, entry));
    await reconcileFinancialLedgerProjection(db, f.companyId, entry.id);
    await reconcileFinancialLedgerProjection(db, f.companyId, entry.id);
  }
  const {runHistoricalLedgerBackfill} = require("../lib/maintenance/rebuild_financial_ledger");
  const report = await runHistoricalLedgerBackfill({projectId: app.options.projectId, companyId: f.companyId,
    fromText: "", toText: "", apply: false, confirmProject: "", confirmCompany: "", pageSize: 100, maxWrites: 500}, db);
  assert.equal(report.ledger.expectedEntries, 2);
  assert.equal(report.ledger.unexpectedExistingEntriesInRange, 0);
  assert.equal(report.reconciliation.totals.receipts.authoritative, 0);
  assert.equal(report.reconciliation.balanced, true);
  assert.equal(report.safeForControlledBackfill, true, JSON.stringify(report.anomalies));
});
