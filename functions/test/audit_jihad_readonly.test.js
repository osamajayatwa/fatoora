"use strict";
const assert = require("node:assert/strict");
const {before, beforeEach, after, test} = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {spawnSync} = require("node:child_process");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw new Error("Dedicated loopback emulator required");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {audit, shareable, writeReports, outsideGit} = require("../scripts/audit_jihad_readonly");
const {emulatorReader, ReadonlyReader, eq, PROJECT, LIMITS} = require("../scripts/jihad_readonly_reader");
const {Findings, analyzeFinance} = require("../scripts/jihad_audit_analysis");
const project = "demo-jihad-readonly", host = process.env.FIRESTORE_EMULATOR_HOST;
const app = initializeApp({projectId: project}, "jihad-audit-fixtures"), db = getFirestore(app);
// Reuse the prior audit's explicitly synthetic trusted-lifecycle evidence.
const archived = require("../../output/integrity-audit/synthetic-lifecycle-snapshot.json");
const pii = "PRIVATE_CUSTOMER_PII_NEVER_EXPORT@example.invalid";
const company = "default_company", uid = "lifecycle-rep";
let requests;
const reader = () => emulatorReader(project, host, (method, body) => requests.push({method, body}));
function timestampFields(value) {
  if (Array.isArray(value)) return value.map(timestampFields);
  if (value && typeof value === "object") {
    if (typeof value._seconds === "number") return new Timestamp(value._seconds, value._nanoseconds || 0);
    return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, timestampFields(entry)]));
  }
  return value;
}
async function seed(mutate = () => {}) {
  const data = structuredClone(archived.collections);
  // hasStock normally comes from the asynchronous custody projection.
  data.rep_inventory_balances.forEach((row) => {row.hasStock = row.quantity > 0;});
  mutate(data);
  const batch = db.batch();
  batch.set(db.doc(`users/${uid}`), {uid, name: "Jihad Synthetic", role: "sales_rep", companyId: company, active: true, approvalStatus: "approved"});
  for (const [collection, rows] of Object.entries(data)) for (const row of rows) {
    const target = collection === "items" ? `items/${row.id}` : `companies/${company}/${collection}/${row.id}`;
    batch.set(db.doc(target), timestampFields({...row, name: pii, email: pii, notes: pii, customerSnapshot: {name: pii, phone: pii}}));
  }
  batch.set(db.doc(`companies/${company}/audit_events/synthetic-invoice-event`), {companyId: company, entityType: "invoice", entityId: "life-sale", action: "invoice.confirmed", occurredAt: Timestamp.now(), actorName: pii});
  await batch.commit();
}
before(() => assert.ok(project.startsWith("demo-") && host.startsWith("127.0.0.1:")));
beforeEach(async () => {
  requests = [];
  const response = await fetch(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`, {method: "DELETE"});
  assert.ok(response.ok);
});
after(() => deleteApp(app));

test("bounded trusted lifecycle reconciles stock and associated finance without raw output", async (t) => {
  await seed();
  const result = await audit(reader());
  assert.deepEqual(result.blockers, []);
  assert.deepEqual(result.confirmedFindings, []);
  assert.equal(result.status, "PASS");
  assert.equal(result.scope.invoiceCount, 1);
  assert.equal(result.environment, "SYNTHETIC_EMULATOR");
  assert.ok(result.checks.length > 20);
  assert.ok(!JSON.stringify(result).includes(pii));
  const summary = JSON.stringify(shareable(result));
  for (const privateValue of [uid, "life-sale", "life-customer", "item_lifecycle-item", pii]) assert.ok(!summary.includes(privateValue));
  assert.ok(requests.every((row) => ["runQuery", "runAggregationQuery", "batchGet"].includes(row.method)));
  assert.ok(requests.slice(1).every((row) => row.body.readTime === result.readTime));
  t.diagnostic("SYNTHETIC_BASELINE_SUMMARY " + JSON.stringify(shareable(result)));
});

function removeSale(data) {
  data.rep_inventory_movements = data.rep_inventory_movements.filter((m) => m.referenceType !== "invoice");
  for (const m of data.rep_inventory_movements) if (["salesReturn", "warehouseReturn"].includes(m.reason)) {
    m.quantityBefore += 3; m.quantityAfter += 3;
  }
  data.rep_inventory_balances[0].quantity += 3;
}
const codes = (result) => result.confirmedFindings.map((finding) => finding.code);

test("missing sale deduction is detected independently even when movements match the cache", async () => {
  await seed(removeSale);
  const result = await audit(reader());
  assert.equal(result.status, "FAIL");
  assert.ok(codes(result).includes("CUSTODY_SOURCE_CLOSING"));
  const delta = result.checks.find((row) => row.code === "CUSTODY_OUT" && row.refs.invoiceId === "life-sale");
  assert.equal(delta.expected, "3.000"); assert.equal(delta.actual, "0.000");
  const closing = result.checks.find((row) => row.code === "CUSTODY_SOURCE_CLOSING");
  assert.equal(closing.expected, "4.000"); assert.equal(closing.actual, "7.000");
});

test("duplicated custody deduction is detected with expected and actual quantities", async () => {
  await seed((data) => {
    const sale = data.rep_inventory_movements.find((m) => m.referenceType === "invoice");
    data.rep_inventory_movements.push({...sale, id: sale.id + "_duplicate", quantityBefore: 5, quantityAfter: 2});
    data.invoices[0].inventoryMovementIds.push(sale.id + "_duplicate");
    for (const m of data.rep_inventory_movements) if (["salesReturn", "warehouseReturn"].includes(m.reason)) {m.quantityBefore -= 3; m.quantityAfter -= 3;}
    data.rep_inventory_balances[0].quantity -= 3;
  });
  const result = await audit(reader());
  assert.equal(result.status, "FAIL"); assert.ok(codes(result).includes("EXCESS_OR_DUPLICATED_CUSTODY_DEDUCTION"));
});

test("warehouse deduction against a custody-sourced invoice is incorrect attribution", async () => {
  await seed((data) => {
    const sale = data.rep_inventory_movements.find((m) => m.referenceType === "invoice");
    removeSale(data);
    const id = sale.id + "_wrong_warehouse";
    data.stock_movements.push({...sale, id, quantityBefore: 12, quantityAfter: 9});
    data.invoices[0].inventoryMovementIds = [id];
  });
  const result = await audit(reader());
  assert.equal(result.status, "FAIL"); assert.ok(codes(result).includes("WRONG_STOCK_ATTRIBUTION"));
});

test("disabled current tracking is a confirmed current risk without assuming historical cause", async () => {
  await seed((data) => {data.items.find((row) => row.id === "item_lifecycle-item").trackStock = false;});
  const result = await audit(reader());
  assert.equal(result.status, "FAIL"); assert.ok(codes(result).includes("DISABLED_TRACKING_WITH_POSITIVE_CUSTODY"));
  assert.equal(result.localFixDeployment, "NOT_QUERIED_OR_ASSUMED");
});

test("missing posting-time tracking evidence blocks conclusions and stops financial reads", async () => {
  await seed((data) => {
    removeSale(data); delete data.invoices[0].items[0].stockTrackedAtPosting;
    data.items.find((row) => row.id === "item_lifecycle-item").trackStock = false;
  });
  const result = await audit(reader());
  assert.equal(result.status, "BLOCKED");
  assert.ok(result.blockers.some((row) => row.code === "DISABLED_TRACKING_HISTORICAL_EVIDENCE_NEEDED"));
  assert.equal(result.coverage.associatedFinance, "NOT_RUN");
  assert.ok(!requests.some((r) => r.body.structuredQuery?.from?.[0]?.collectionId === "receipts"));
});

test("inconsistent custody cache and stale visibility are independently identified", async () => {
  await seed((data) => {data.rep_inventory_balances[0].quantity = 99; data.rep_inventory_balances[0].hasStock = false;});
  const result = await audit(reader());
  assert.equal(result.status, "FAIL");
  assert.ok(codes(result).includes("CUSTODY_MOVEMENT_CLOSING"));
  assert.ok(codes(result).includes("CUSTODY_VISIBILITY_PROJECTION"));
});

test("ambiguous actual representative profiles stop before inventory reads", async () => {
  await seed();
  await db.doc("users/second-jihad").set({uid: "second-jihad", name: "Jihad Second", role: "sales_rep", companyId: company});
  const result = await audit(reader());
  assert.equal(result.status, "BLOCKED"); assert.equal(result.scope.invoiceCount, 0);
  assert.ok(result.blockers.some((row) => row.code === "AMBIGUOUS_JIHAD_IDENTITY"));
  assert.ok(requests.every((r) => !r.body.documents && (r.body.structuredQuery || r.body.structuredAggregationQuery?.structuredQuery).from[0].collectionId === "users"));
});

test("more than 200 relevant invoices blocks before fetching invoice documents", async () => {
  await seed();
  const batch = db.batch();
  for (let i = 0; i < 200; i++) batch.set(db.doc(`companies/${company}/invoices/limit-${i}`), {companyId: company, salesRepId: uid});
  await batch.commit();
  const result = await audit(reader());
  assert.equal(result.status, "BLOCKED"); assert.equal(result.scope.invoiceCount, 0);
  assert.ok(result.blockers.some((row) => row.code === "INVOICES_LIMIT"));
  assert.ok(!requests.some((r) => r.method === "runQuery" && r.body.structuredQuery.from[0].collectionId === "invoices"));
});

test("exactly 200 relevant invoices paginate completely without reading a 201st invoice", async () => {
  await seed(); const batch = db.batch();
  for (let i = 0; i < 199; i++) batch.set(db.doc(`companies/${company}/invoices/draft-${String(i).padStart(3, "0")}`), {
    companyId: company, salesRepId: uid, invoiceStatus: "draft", financialPosted: false, inventoryPosted: false, items: [],
  });
  await batch.commit();
  const result = await audit(reader());
  assert.equal(result.status, "PASS"); assert.equal(result.scope.invoiceCount, 200);
  const pages = requests.filter((r) => r.method === "runQuery" && r.body.structuredQuery.from[0].collectionId === "invoices");
  assert.equal(pages.length, 8); assert.ok(pages.every((p) => p.body.structuredQuery.limit <= 25));
  assert.equal(new Set(result.invoiceReview.map((row) => row.invoiceId)).size, 200);
});

test("missing custody opening chronology blocks a trusted closing result", async () => {
  await seed((data) => {data.rep_inventory_movements = data.rep_inventory_movements.filter((m) => m.reason !== "warehouseDelivery");});
  const result = await audit(reader());
  assert.equal(result.status, "BLOCKED");
  assert.ok(result.blockers.some((row) => row.code === "CUSTODY_OPENING_OR_CHAIN_HISTORY_INCOMPLETE"));
});

test("customer history requiring another rep's invoice stops at a count-only boundary", async () => {
  await seed();
  await db.doc(`companies/${company}/invoices/unrelated-never-fetch`).set({companyId: company, salesRepId: "other-rep", customerId: "life-customer", financialPosted: true});
  const result = await audit(reader());
  assert.equal(result.status, "BLOCKED"); assert.equal(result.scope.invoiceCount, 1);
  assert.ok(result.blockers.some((row) => row.code === "CUSTOMER_HISTORY_OUTSIDE_APPROVED_SCOPE"));
  assert.ok(!requests.some((r) => (r.body.documents || []).some((name) => name.endsWith("/unrelated-never-fetch"))));
});

test("partial payment cache cannot count later collections as initial cash", async () => {
  await seed((data) => {data.invoices[0].paidAmount = 20; data.invoices[0].remainingAmount = 10;});
  const result = await audit(reader());
  assert.equal(result.status, "FAIL"); assert.ok(codes(result).includes("INVOICE_PAID_ALLOCATION"));
  const paid = result.checks.find((row) => row.code === "INVOICE_PAID_ALLOCATION");
  assert.equal(paid.expected, "30.000"); assert.equal(paid.actual, "20.000");
});

test("duplicate collection cash and journal pairs are detected", async () => {
  await seed((data) => {
    const cash = data.cash_movements.find((row) => row.sourceCollection === "receipts" && row.customerId === "life-customer");
    data.cash_movements.push({...cash, id: cash.id + "_duplicate", balanceBefore: 30, balanceAfter: 50});
    const entry = data.financial_ledger_entries.find((row) => row.sourceCollection === "invoices");
    data.financial_ledger_entries.push({...entry, id: entry.id + "_duplicate"});
  });
  const result = await audit(reader());
  assert.equal(result.status, "FAIL"); assert.ok(codes(result).includes("SOURCE_CASH_EFFECT"));
  assert.ok(codes(result).includes("FINANCIAL_ACCOUNT_PAIR"));
});

test("invoice journal ownership is checked against the original invoice attribution", async () => {
  await seed((data) => {data.financial_ledger_entries.find((row) => row.sourceCollection === "invoices").salesRepId = "incorrect-owner";});
  const result = await audit(reader());
  assert.equal(result.status, "FAIL"); assert.ok(codes(result).includes("INVOICE_JOURNAL_ATTRIBUTION_MISMATCH"));
});

test("initial cash uses the posting snapshot when draft creator and collector differ", async () => {
  await seed((data) => {data.invoices[0].createdByRole = "admin";});
  const result = await audit(reader()); assert.equal(result.status, "PASS");
});

test("missing initial cash account snapshot does not infer the collector from the draft creator", async () => {
  await seed((data) => {delete data.invoices[0].initialCashAccount;});
  const result = await audit(reader()); assert.equal(result.status, "BLOCKED");
  assert.ok(result.blockers.some((row) => row.code === "INITIAL_CASH_ACCOUNT_HISTORY_INCOMPLETE"));
  assert.ok(!result.checks.some((row) => row.code === "CUSTOMER_SOURCE_CLOSING"));
});

test("missing historical receipt ownership stops without inventing customer closing differences", async () => {
  await seed((data) => {delete data.receipts.find((row) => row.id === "receipt_life-receipt").financialLedgerOwnerGroups;});
  const result = await audit(reader());
  assert.equal(result.status, "BLOCKED"); assert.ok(result.blockers.some((row) => row.code === "RECEIPT_OWNERSHIP_EVIDENCE_MISSING"));
  assert.ok(!result.checks.some((row) => row.code === "CUSTOMER_SOURCE_CLOSING"));
});

test("a posting link to another already-loaded source cannot silently pass", async () => {
  await seed((data) => {
    data.invoices[0].cashMovementIds = data.cash_movements.filter((row) => row.sourceCollection === "receipts" && row.customerId === "life-customer").map((row) => row.id);
  });
  const result = await audit(reader());
  assert.equal(result.status, "FAIL"); assert.ok(codes(result).includes("FINANCIAL_POSTING_LINK_MISMATCH"));
});

test("cached return quantities are checked against actual confirmed returns", async () => {
  await seed((data) => {data.invoices[0].returnedQuantitiesByItem = {"life-sale:line:life-line": 0};});
  const result = await audit(reader());
  assert.equal(result.status, "FAIL"); assert.ok(codes(result).includes("RETURN_CACHED_QUANTITY"));
});

test("unsupported monetary precision blocks instead of silently rounding", async () => {
  await seed((data) => {data.rep_inventory_balances[0].quantity = 0.0001;});
  const result = await audit(reader());
  assert.equal(result.status, "BLOCKED"); assert.ok(result.blockers.some((row) => row.code === "INVALID_NUMERIC_OR_SOURCE_DATA"));
});

test("one fixed server read timestamp protects against changing live projections", async () => {
  await seed(); const r = reader();
  await r.count("users", eq("name", "Jihad Synthetic"));
  await db.doc(`companies/${company}/rep_inventory_balances/${uid}_item_lifecycle-item`).update({quantity: 99});
  const result = await audit(r);
  assert.equal(result.status, "PASS");
  assert.equal(result.custody.find((row) => row.itemId === "item_lifecycle-item").persisted, "4.000");
  assert.equal((await db.doc(`companies/${company}/rep_inventory_balances/${uid}_item_lifecycle-item`).get()).data().quantity, 99);
});

test("permission errors are sanitized and cannot trigger credential/policy workarounds", async () => {
  const r = new ReadonlyReader({project, emulator: true, request: async () => {throw Object.assign(new Error(pii), {response: {status: 403, data: {secret: pii}}});}});
  const result = await audit(r);
  assert.equal(result.status, "BLOCKED"); assert.equal(result.scope.invoiceCount, 0);
  assert.ok(result.blockers.some((row) => row.code === "PERMISSION_DENIED"));
  assert.ok(!JSON.stringify(result).includes(pii));
});

test("RPC and environment boundaries reject writes and production emulator authentication", async () => {
  const r = reader();
  await assert.rejects(() => r.rpc("commit", {}), (e) => e.code === "NON_READ_RPC_REJECTED");
  assert.equal(requests.length, 0);
  assert.throws(() => emulatorReader(PROJECT, host), (e) => e.code === "INVALID_EMULATOR_CONTEXT");
  assert.throws(() => emulatorReader(project, "firestore.googleapis.com:443"), (e) => e.code === "INVALID_EMULATOR_CONTEXT");
});

test("mismatched read timestamps fail closed", async () => {
  let call = 0;
  const r = new ReadonlyReader({project, emulator: true, request: async () => [{readTime: `2026-11-02T00:00:0${call++}Z`, result: {aggregateFields: {n: {integerValue: "0"}}}}]});
  const result = await audit(r);
  assert.equal(result.status, "BLOCKED"); assert.ok(result.blockers.some((row) => row.code === "INCONSISTENT_READ_TIME"));
});

test("request and time budgets stop before another remote call", async () => {
  const r = reader(); r.counts.requests = LIMITS.requests;
  await assert.rejects(() => r.count("users", eq("name", "Jihad")), (e) => e.code === "REQUEST_OR_TIME_BUDGET");
  assert.equal(requests.length, 0);
});

test("reports are derived-only outside Git, never overwritten or written through a repository junction", async () => {
  await seed(); const result = await audit(reader());
  assert.throws(() => outsideGit(path.resolve(__dirname, "../../output/private")), (e) => e.code === "REPORT_OUTPUT_INSIDE_REPOSITORY");
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "fatoora-jihad-test-"));
  try {
    writeReports(result, path.join(temp, "private"));
    const detail = JSON.parse(fs.readFileSync(path.join(temp, "private/findings.private.json"), "utf8"));
    assert.ok(!JSON.stringify(detail).includes(pii)); assert.ok(!("collections" in detail));
    assert.throws(() => writeReports(result, path.join(temp, "private")), (e) => e.code === "EEXIST");
    fs.mkdirSync(path.join(temp, "gitrepo/.git"), {recursive: true});
    assert.throws(() => outsideGit(path.join(temp, "gitrepo/results")), (e) => e.code === "REPORT_OUTPUT_INSIDE_GIT");
    if (process.platform === "win32") {
      fs.symlinkSync(path.resolve(__dirname, "../.."), path.join(temp, "junction"), "junction");
      assert.throws(() => outsideGit(path.join(temp, "junction/results")), (e) => e.code === "REPORT_OUTPUT_INSIDE_REPOSITORY");
      fs.unlinkSync(path.join(temp, "junction"));
    }
  } finally {
    const resolved = fs.realpathSync(temp);
    assert.ok(path.basename(resolved).startsWith("fatoora-jihad-test-") && path.dirname(resolved).toLowerCase() === fs.realpathSync(os.tmpdir()).toLowerCase());
    fs.rmSync(resolved, {recursive: true, force: true});
  }
});

test("CLI help and rejection of mutation flags do not authenticate", () => {
  const script = path.resolve(__dirname, "../scripts/audit_jihad_readonly.js");
  const help = spawnSync(process.execPath, [script, "--help"], {encoding: "utf8"});
  assert.equal(help.status, 0); assert.match(help.stdout, /200-invoice ceiling/);
  const denied = spawnSync(process.execPath, [script, `--project=${PROJECT}`, "--apply"], {encoding: "utf8"});
  assert.equal(denied.status, 2); assert.equal(JSON.parse(denied.stdout).code, "INVALID_ARGUMENTS");
});

test("exact invoice arithmetic detects the known half-thousandth historical discrepancy", () => {
  const invoice = {id: "rounding", invoiceStatus: "confirmed", financialPosted: true, customerId: "c", createdByRole: "admin", salesRepId: "rep",
    grandTotal: 1.783, initialPaidAmount: 0, paidAmount: 0, remainingAmount: 1.783,
    items: [{quantity: 0.41, unitPrice: 4.35, discount: 0, taxPercent: 0, subtotal: 1.783, taxAmount: 0, total: 1.783}]};
  const result = new Findings();
  analyzeFinance({invoices: [invoice], receipts: [], sales_returns: [], cash_movements: [],
    customer_transactions: [{id: "debit", sourceCollection: "invoices", sourceId: "rounding", customerId: "c", debitAmount: 1.783, creditAmount: 0, balanceBefore: 0, balanceAfter: 1.783}],
    financial_ledger_entries: [{id: "journal", sourceCollection: "invoices", sourceId: "rounding", salesRepId: "rep", customerId: "c", amount: 1.783, debitAccountKey: "customer:c", creditAccountKey: "sales"}],
    customers: [{id: "c", currentBalance: 1.783, totalSales: 1.783, totalPaid: 0}], customerCoverage: {c: true}}, {id: "rep"}, result);
  assert.equal(result.status, "FAIL");
  const difference = result.findings.find((row) => row.code === "LINE_SUBTOTAL_ARITHMETIC");
  assert.equal(difference.expected, "1.784"); assert.equal(difference.actual, "1.783");
});

for (const [method, account] of [["bank", "bank_unallocated"], ["check", "check_clearing"], ["cliq", "cliq_clearing"]]) {
  test(`${method} collection preserves its documented account and creates no physical cash`, async () => {
    await seed((data) => {
      const receipt = data.receipts.find((r) => r.id === "receipt_life-receipt");
      receipt.paymentMethod = method; receipt.cashMovementIds = [];
      data.cash_movements = data.cash_movements.filter((m) => m.sourceId !== receipt.id);
      for (const entry of data.financial_ledger_entries.filter((e) => e.sourceId === receipt.id)) {entry.debitAccountKey = account; entry.paymentMethod = method;}
    });
    const result = await audit(reader());
    assert.equal(result.status, "PASS");
    assert.equal(result.coverage.companyAndRepCashClosing, "OUTSIDE_APPROVED_SCOPE");
  });
}

test("unknown historical Visa method blocks instead of being reclassified or inventing AR differences", async () => {
  await seed((data) => {data.receipts.find((r) => r.id === "receipt_life-receipt").paymentMethod = "visa";});
  const result = await audit(reader());
  assert.equal(result.status, "BLOCKED");
  assert.ok(result.blockers.some((row) => row.code === "UNKNOWN_PAYMENT_METHOD_NO_RECLASSIFICATION"));
  assert.ok(!result.checks.some((row) => row.code === "CUSTOMER_SOURCE_CLOSING"));
});

function addCancellation(data, removeInverse = false) {
  const receiptId = "cancelled-linked-bank";
  data.invoices[0].cancelledReceiptIds = [receiptId];
  data.receipts.push({id: receiptId, companyId: company, customerId: "life-customer", amount: 5,
    paymentMethod: "bank", status: "cancelled", cancellationVersion: 1, invoiceAllocations: {"life-sale": 5},
    customerTransactionIds: ["cancelled-original-credit"], cancellationCustomerTransactionIds: ["cancelled-inverse-debit"],
    cashMovementIds: [], cancellationCashMovementIds: [], receiptLedgerOwnershipVersion: 1, financialLedgerOwnerGroups: [{salesRepId: uid, amount: 5}]});
  for (const row of [
    {id: "cancelled-original-credit", debitAmount: 0, creditAmount: 5, balanceBefore: -10, balanceAfter: -15},
    {id: "cancelled-inverse-debit", debitAmount: 5, creditAmount: 0, balanceBefore: -15, balanceAfter: -10},
  ]) data.customer_transactions.push({...row, companyId: company, customerId: "life-customer", sourceCollection: "receipts", sourceId: receiptId});
  data.financial_ledger_entries.push({id: "cancelled-original-journal", companyId: company, customerId: "life-customer", salesRepId: uid, sourceCollection: "receipts", sourceId: receiptId, amount: 5, debitAccountKey: "bank_unallocated", creditAccountKey: "customer:life-customer"});
  if (!removeInverse) data.financial_ledger_entries.push({id: "cancelled-inverse-journal", companyId: company, customerId: "life-customer", salesRepId: uid, sourceCollection: "receipts", sourceId: receiptId, amount: 5, debitAccountKey: "customer:life-customer", creditAccountKey: "bank_unallocated", isReversal: true, reversesEntryId: "cancelled-original-journal"});
}

test("linked receipt cancellation retains original and inverse without counting collection twice", async () => {
  await seed((data) => addCancellation(data));
  const result = await audit(reader()); assert.equal(result.status, "PASS");
});

test("a missing cancellation journal cannot hide behind zero net customer effect", async () => {
  await seed((data) => addCancellation(data, true));
  const result = await audit(reader()); assert.equal(result.status, "FAIL");
  assert.ok(codes(result).includes("FINANCIAL_ACCOUNT_PAIR"));
});

function cashRefund(data, wrongAccount = false) {
  const returned = data.sales_returns[0], id = "verified-cash-refund";
  Object.assign(returned, {refundType: "cash_refund", customerCreditAmount: 0, cashRefundAmount: 10, cashMovementIds: [id]});
  returned.customerTransactionIds.push("refund-debit");
  Object.assign(data.invoices[0], {customerCreditAmount: 0, cashRefundAmount: 10});
  const customer = data.customers.find((c) => c.id === "life-customer"); customer.currentBalance = 0; customer.totalPaid = 20;
  data.customer_transactions.push({id: "refund-debit", companyId: company, customerId: "life-customer", sourceCollection: "sales_returns", sourceId: returned.id,
    debitAmount: 10, creditAmount: 0, balanceBefore: -10, balanceAfter: 0});
  data.cash_movements.push({id, companyId: company, customerId: "life-customer", sourceCollection: "sales_returns", sourceId: returned.id,
    cashAccount: wrongAccount ? "company_cash" : "rep_cash", salesRepId: wrongAccount ? "" : uid, direction: "out", amount: 10, balanceBefore: 30, balanceAfter: 20});
  data.financial_ledger_entries.push({id: "refund-journal", companyId: company, customerId: "life-customer", sourceCollection: "sales_returns", sourceId: returned.id,
    salesRepId: uid, amount: 10, debitAccountKey: "customer:life-customer", creditAccountKey: wrongAccount ? "company_cash" : `rep_cash:${uid}`});
}

test("cash refund reconciles to actual original collections, customer delta and journal", async () => {
  await seed((data) => cashRefund(data));
  const result = await audit(reader()); assert.equal(result.status, "PASS");
});

test("cash refund from an unverified collection account stops without fabricating cash provenance", async () => {
  await seed((data) => cashRefund(data, true));
  const result = await audit(reader()); assert.equal(result.status, "BLOCKED");
  assert.ok(result.blockers.some((row) => row.code === "REFUND_COLLECTION_PROVENANCE_MISSING"));
});

test("legacy initial payment without original cash/customer evidence remains unresolved", async () => {
  await seed((data) => {
    delete data.invoices[0].initialPaidAmount;
    data.invoices[0].customerTransactionIds = data.invoices[0].customerTransactionIds.filter((id) => !id.endsWith("_payment"));
    data.invoices[0].cashMovementIds = [];
    data.customer_transactions = data.customer_transactions.filter((row) => row.id !== "life-sale_payment");
    data.cash_movements = data.cash_movements.filter((row) => row.sourceCollection !== "invoices");
  });
  const result = await audit(reader()); assert.equal(result.status, "BLOCKED");
  assert.ok(result.blockers.some((row) => row.code === "INITIAL_PAYMENT_HISTORY_INCOMPLETE"));
  assert.ok(!result.checks.some((row) => row.code === "CUSTOMER_SOURCE_CLOSING"));
});
