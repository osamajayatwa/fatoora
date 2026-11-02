"use strict";
const assert = require("node:assert/strict");
const {before, after, test} = require("node:test");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {reassignCustomer, reassignCustomerTransaction, customerAssignedTo} = require("../lib/trusted/customer_assignment");
const {createCustomerTransaction, updateCustomerTransaction} = require("../lib/trusted/customer_profiles");
const {confirmInvoiceTransaction} = require("../lib/trusted/confirm_invoice");
const {createReceiptTransaction} = require("../lib/trusted/create_receipt");
const {cancelReceiptTransaction} = require("../lib/trusted/cancel_receipt");
const {confirmSalesReturnTransaction} = require("../lib/trusted/confirm_sales_return");
const {legacyAssignmentUpdate, legacyAssignmentRollback} = require("../scripts/backfill_customer_assignment");
const {listAccessibleCustomers, listAccessibleCustomersPage} = require("../lib/trusted/customer_queries");
const app = initializeApp({projectId: "fatoora-phase4-assignment-test"});
const db = getFirestore(app);
let sequence = 0;
before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Local emulator required");
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${app.options.projectId}/databases/(default)/documents`, {method: "DELETE"});
});
after(() => deleteApp(app));
async function fixture({creator = "rep", legacy = false} = {}) {
  const companyId = `assignment-${++sequence}`;
  const path = (name, id) => db.doc(`companies/${companyId}/${name}/${id}`);
  const admin = `${companyId}-admin`, repA = `${companyId}-a`, repB = `${companyId}-b`;
  for (const [uid, role] of [[admin, "admin"], [repA, "sales_rep"], [repB, "sales_rep"]]) {
    await db.doc(`users/${uid}`).set({uid, role, companyId, name: uid, active: true, approvalStatus: "approved"});
  }
  const uid = creator === "admin" ? admin : repA;
  const {customerId} = await createCustomerTransaction(db, uid, companyId, "assignment-customer", {name: "Customer", active: true});
  if (legacy) {
    const {FieldValue} = require("firebase-admin/firestore");
    await path("customers", customerId).update({assignedToUid: FieldValue.delete(), assignedToName: FieldValue.delete(), assignedToRole: FieldValue.delete(), assignmentVersion: FieldValue.delete(), assignmentRevision: FieldValue.delete()});
  }
  const customer = async () => (await path("customers", customerId).get()).data();
  const request = async (target, key = "assignment-operation") => {
    const current = await customer();
    return {companyId, customerId, assignedToUid: target, idempotencyKey: key, reason: "Territory transfer",
      expectedAssignedToUid: current.assignedToUid ?? current.createdByUid, expectedAssignmentRevision: current.assignmentRevision ?? 0};
  };
  const transfer = async (target, key) => reassignCustomerTransaction(db, admin, await request(target, key));
  const draft = async (id, owner) => path("invoices", id).set({id, companyId, invoiceNumber: `INV-${id}`, invoiceStatus: "draft",
    customerId, customerSnapshot: {id: customerId, name: "Customer"}, createdByUid: owner, createdByName: owner, createdByRole: "sales_rep",
    salesRepId: owner, salesRepName: owner, invoiceDate: Timestamp.now(), dueDate: Timestamp.now(),
    stockSourceType: "salesRep", stockSourceSalesRepId: owner, stockSourceId: owner, hasReceivedPayment: false,
    paidAmount: 0, isLocked: false, financialPosted: false, inventoryPosted: false,
    items: [{lineId: "line", lineType: "custom", itemId: null, itemName: "Service", description: "At site", unit: "service",
      quantity: 2, unitPrice: 50, discount: 0, taxPercent: 0}]});
  const rows = async (name) => (await db.collection(`companies/${companyId}/${name}`).get()).docs.map((doc) => doc.data());
  return {companyId, admin, repA, repB, path, customerId, customer, request, transfer, draft, rows};
}

test("mixed legacy and assigned customer pages fill past transferred records without leaks or duplicates", async () => {
  const f = await fixture({legacy: true});
  await f.path("customers", f.customerId).update({active: false});
  const seed = async (id, overrides) => f.path("customers", id).set({
    id, companyId: f.companyId, createdByUid: f.repA, active: true,
    name: id, nameLower: id, searchKeywords: ["customer", "عميل قديم"], currentBalance: 10, ...overrides,
  });
  // More excluded creator candidates than a whole query batch, both before and
  // between authorized records. A client filter after limit would lose pages.
  for (let index = 0; index < 9; index++) await seed(`a-old-${index}`, {assignmentVersion: 1, assignedToUid: f.repB});
  await seed("b-legacy", {});
  await seed("c-ambiguous", {assignedToUid: f.repB}); // unversioned is still creator-owned
  for (let index = 0; index < 9; index++) await seed(`d-old-${index}`, {assignmentVersion: 1, assignedToUid: f.repB});
  await seed("e-current", {assignmentVersion: 1, assignedToUid: f.repA});
  await seed("f-incoming", {createdByUid: f.repB, assignmentVersion: 1, assignedToUid: f.repA});
  await seed("g-other-legacy", {createdByUid: f.repB});
  await seed("h-invalid-explicit", {assignmentVersion: 1, assignedToUid: ""});
  await seed("i-inactive", {active: false});
  const before = await f.rows("customers");
  const request = {companyId: f.companyId, pageSize: 2};
  const first = await listAccessibleCustomersPage(db, f.repA, request);
  assert.deepEqual(first.customers.map((c) => c.id), ["b-legacy", "c-ambiguous"]);
  assert.equal(first.hasMore, true);
  const second = await listAccessibleCustomersPage(db, f.repA, {...request, after: first.cursor});
  assert.deepEqual(second.customers.map((c) => c.id), ["e-current", "f-incoming"]);
  assert.equal(second.hasMore, false);
  for (const term of [" customer ", "عميل قديم"]) {
    const found = await listAccessibleCustomersPage(db, f.repA, {...request, searchText: term});
    assert.deepEqual(found.customers.map((c) => c.id), ["b-legacy", "c-ambiguous"]);
    assert.equal(found.hasMore, true);
  }
  const allA = await listAccessibleCustomersPage(db, f.repA, {...request, activeOnly: false, pageSize: 100});
  assert.equal(allA.customers.length, 6);
  const allB = await listAccessibleCustomersPage(db, f.repB, {...request, pageSize: 100});
  assert.equal(allB.customers.length, 19);
  assert.ok(!allB.customers.some((c) => ["b-legacy", "c-ambiguous", "e-current", "f-incoming"].includes(c.id)));
  const admin = await listAccessibleCustomersPage(db, f.admin, {...request, activeOnly: false, pageSize: 100});
  assert.equal(admin.customers.length, before.length);
  assert.deepEqual(await f.rows("customers"), before, "Listing never migrates or writes customers");
});

test("legacy receivable pages, totals and dashboard include old debt without transferred balances", async () => {
  const f = await fixture({legacy: true});
  await f.path("customers", f.customerId).update({currentBalance: 80});
  for (const [id, balance, assignment] of [["outgoing", 900, {assignmentVersion: 1, assignedToUid: f.repB}],
    ["incoming", 40, {assignmentVersion: 1, assignedToUid: f.repA, createdByUid: f.repB}],
    ["credit", -20, {}], ["inactive", 700, {active: false}]]) {
    await f.path("customers", id).set({id, companyId: f.companyId, active: true, nameLower: id,
      createdByUid: f.repA, currentBalance: balance, ...assignment});
  }
  const request = {companyId: f.companyId, order: "balance", pageSize: 1, includeTotals: true};
  const first = await listAccessibleCustomersPage(db, f.repA, request);
  assert.equal(first.customers[0].id, f.customerId);
  assert.equal(first.totalReceivables, 120);
  assert.equal(first.customerCount, 3);
  assert.equal(first.hasMore, true);
  const second = await listAccessibleCustomersPage(db, f.repA, {...request, after: first.cursor});
  assert.equal(second.customers[0].id, "incoming");
  assert.equal(second.hasMore, false);
  const {getDashboardSnapshot} = require("../lib/trusted/dashboard_reporting");
  const dashboard = await getDashboardSnapshot.run({auth: {uid: f.repA}, data: {companyId: f.companyId, from: 0, to: Date.now()}});
  assert.equal(dashboard.totalReceivables, 120);
  assert.equal(dashboard.customerCount, 3);
  const admin = await listAccessibleCustomersPage(db, f.admin, request);
  assert.equal(admin.totalReceivables, 1020);
});

test("customer callable enforces current role/company and rejects forged cursor/filter scope", async () => {
  const f = await fixture({legacy: true});
  const request = {companyId: f.companyId, pageSize: 1};
  const before = await f.customer();
  const page = await listAccessibleCustomersPage(db, f.repA, {...request, salesRepId: f.repB, uid: f.repB});
  assert.equal(page.customers[0].id, f.customerId, "Requested UID cannot override authentication");
  await assert.rejects(listAccessibleCustomers.run({data: request}), (error) => error.code === "unauthenticated");
  const other = await fixture();
  await assert.rejects(listAccessibleCustomersPage(db, other.admin, request), (error) => error.code === "permission-denied");
  await db.doc(`users/${f.repB}`).update({active: false});
  await assert.rejects(listAccessibleCustomersPage(db, f.repB, request), (error) => error.code === "permission-denied");
  for (const extra of [{order: "balance", after: page.cursor}, {searchText: "different", after: page.cursor},
    {after: {...page.cursor, id: "a/b"}}, {pageSize: 1000}, {companyId: "bad/id"}]) {
    await assert.rejects(listAccessibleCustomersPage(db, f.repA, {...request, ...extra}), (error) => error.code === "invalid-argument");
  }
  await db.doc(`users/${f.repB}`).update({active: true});
  await f.transfer(f.repB);
  assert.deepEqual((await listAccessibleCustomersPage(db, f.repA, request)).customers, []);
  assert.equal((await listAccessibleCustomersPage(db, f.repB, request)).customers[0].id, f.customerId);
  assert.equal((await f.customer()).createdByUid, before.createdByUid);
});

test("unmigrated customer can update, invoice and collect with creator authorization, other rep is denied", async () => {
  const f = await fixture({legacy: true});
  await assert.rejects(updateCustomerTransaction(db, f.repB, f.companyId, f.customerId, {name: "Denied"}), (error) => error.code === "permission-denied");
  await updateCustomerTransaction(db, f.repA, f.companyId, f.customerId, {name: "Legacy updated"});
  await f.draft("legacy-sale", f.repA);
  await confirmInvoiceTransaction(db, f.repA, f.companyId, "legacy-sale");
  const input = {customerId: f.customerId, amount: 25, paymentMethod: "cash", receiptDate: Date.now()};
  await assert.rejects(createReceiptTransaction(db, f.repB, f.companyId, "denied-legacy-payment", input), (error) => error.code === "permission-denied");
  await createReceiptTransaction(db, f.repA, f.companyId, "legacy-payment", input);
  assert.equal((await f.customer()).currentBalance, 75);
  assert.equal((await f.customer()).assignmentVersion, undefined, "Ordinary operations do not silently migrate ownership");
});

test("Admin-created legacy customers stay Admin-only until an explicit transfer, and Rep-to-Admin revokes Rep access", async () => {
  const f = await fixture({creator: "admin", legacy: true});
  const input = {companyId: f.companyId};
  assert.equal((await listAccessibleCustomersPage(db, f.admin, input)).customers[0].id, f.customerId);
  for (const uid of [f.repA, f.repB]) assert.deepEqual((await listAccessibleCustomersPage(db, uid, input)).customers, []);
  await f.transfer(f.repA, "legacy-admin-to-rep");
  assert.equal((await listAccessibleCustomersPage(db, f.repA, input)).customers[0].id, f.customerId);
  await f.transfer(f.admin, "legacy-rep-to-admin");
  assert.deepEqual((await listAccessibleCustomersPage(db, f.repA, input)).customers, []);
  assert.equal((await listAccessibleCustomersPage(db, f.admin, input)).customers[0].id, f.customerId);
  assert.equal((await f.customer()).createdByUid, f.admin);
});

test("Admin to Rep, Rep to Rep, and Rep to Admin preserve creator and record each transfer", async () => {
  const f = await fixture({creator: "admin"});
  const original = await f.customer();
  for (const [index, target] of [f.repA, f.repB, f.admin].entries()) {
    await f.transfer(target, `assignment-event-${index}`);
    const customer = await f.customer();
    assert.equal(customer.assignedToUid, target);
    assert.equal(customer.assignmentRevision, index + 1);
    for (const field of ["createdByUid", "createdByName", "createdByRole", "createdAt", "currentBalance", "totalSales", "totalPaid"]) {
      assert.deepEqual(customer[field], original[field], field);
    }
  }
  const history = await f.rows("customer_assignment_events");
  assert.equal(history.length, 3);
  assert.ok(history.every((event) => event.actorUid === f.admin && event.reason === "Territory transfer"));
});
test("reassignment is idempotent and a stale competing transfer cannot overwrite the winner", async () => {
  const f = await fixture();
  const input = await f.request(f.repB);
  assert.equal((await reassignCustomerTransaction(db, f.admin, input)).alreadyReassigned, false);
  const once = await f.customer();
  assert.equal((await reassignCustomerTransaction(db, f.admin, input)).alreadyReassigned, true);
  assert.deepEqual(await f.customer(), once);
  await assert.rejects(reassignCustomerTransaction(db, f.admin, {...input, assignedToUid: f.admin}), (error) => error.code === "already-exists");
  await assert.rejects(reassignCustomerTransaction(db, f.admin, {...input, assignedToUid: f.admin, idempotencyKey: "different-event"}),
    (error) => error.details?.reason === "customer-assignment-stale");
});
test("unapproved, inactive, foreign-company, Sales Rep and unauthenticated requests cannot transfer", async () => {
  const f = await fixture();
  const input = await f.request(f.repB);
  await assert.rejects(reassignCustomer.run({data: input}), (error) => error.code === "unauthenticated");
  for (const uid of [f.repA, f.repB, undefined]) {
    await assert.rejects(reassignCustomerTransaction(db, uid, input), (error) => ["permission-denied", "unauthenticated"].includes(error.code));
  }
  for (const override of [{active: false}, {approvalStatus: "pending"}, {companyId: "another-company"}, {role: "pending_sales_rep"}]) {
    const uid = `${f.companyId}-invalid-${Object.keys(override)[0]}`;
    await db.doc(`users/${uid}`).set({role: "sales_rep", companyId: f.companyId, active: true, approvalStatus: "approved", ...override});
    await assert.rejects(reassignCustomerTransaction(db, f.admin, {...input, assignedToUid: uid}), (error) => error.code === "permission-denied");
  }
  assert.equal((await f.customer()).assignedToUid, f.repA);
  assert.equal((await f.rows("customer_assignment_events")).length, 0);
});
test("explicit assignment wins over creator; legacy migration copies the creator without financial changes", async () => {
  const f = await fixture({legacy: true});
  const before = await f.customer();
  assert.equal(customerAssignedTo(before, f.repA), true);
  assert.equal(customerAssignedTo({...before, assignedToUid: f.repB}, f.repA), true);
  assert.equal(customerAssignedTo({...before, assignedToUid: f.repB}, f.repB), false);
  assert.throws(() => legacyAssignmentUpdate({...before, assignedToUid: f.repB}, {}, f.companyId));
  const update = legacyAssignmentUpdate(before, (await db.doc(`users/${f.repA}`).get()).data(), f.companyId);
  assert.equal(update.assignedToUid, before.createdByUid);
  assert.ok(!Object.keys(update).some((key) => ["createdByUid", "currentBalance", "totalSales", "totalPaid", "updatedAt"].includes(key)));
  await f.path("customers", f.customerId).update(update);
  assert.equal(legacyAssignmentUpdate(await f.customer(), {}, f.companyId), null);
  const rollback = legacyAssignmentRollback(await f.customer(), f.companyId);
  await f.path("customers", f.customerId).update(rollback);
  assert.equal((await f.customer()).assignedToUid, undefined);
  assert.equal(legacyAssignmentRollback(await f.customer(), f.companyId), null);
  await f.path("customers", f.customerId).update(update);
  await f.transfer(f.repB);
  const transferred = await f.customer();
  assert.throws(() => legacyAssignmentRollback(transferred, f.companyId));
  assert.equal(customerAssignedTo(await f.customer(), f.repA), false);
  assert.equal(customerAssignedTo(await f.customer(), f.repB), true);
  assert.equal(customerAssignedTo({...before, assignedToUid: "", assignmentVersion: 1}, f.repA), false);
  assert.throws(() => legacyAssignmentUpdate(before, undefined, f.companyId));
});
test("legacy customers can be explicitly transferred without first changing their original creator", async () => {
  const f = await fixture({legacy: true});
  await f.transfer(f.repB);
  assert.equal((await f.customer()).createdByUid, f.repA);
  assert.equal((await f.customer()).assignedToUid, f.repB);
  assert.equal((await f.rows("customer_assignment_events"))[0].legacyAssignment, true);
});
test("transfer itself leaves historical invoices, receipts, returns, cash, custody and ledgers unchanged", async () => {
  const f = await fixture();
  await f.draft("old", f.repA);
  await confirmInvoiceTransaction(db, f.repA, f.companyId, "old");
  const original = {id: "existing", companyId: f.companyId, salesRepId: f.repA, amount: 5};
  for (const name of ["quotations", "receipts", "sales_returns", "cash_movements", "cash_balances", "rep_inventory_balances"]) {
    await f.path(name, "existing").set(original);
  }
  const names = ["invoices", "quotations", "receipts", "sales_returns", "cash_movements", "cash_balances", "rep_inventory_balances", "customer_transactions", "financial_ledger_entries"];
  const before = await Promise.all(names.map(f.rows));
  await f.transfer(f.repB);
  assert.deepEqual(await Promise.all(names.map(f.rows)), before);
});
test("new rep operates; old rep cannot edit customer or confirm stale drafts after transfer", async () => {
  const f = await fixture();
  await f.draft("stale", f.repA);
  await f.transfer(f.repB);
  await assert.rejects(updateCustomerTransaction(db, f.repA, f.companyId, f.customerId, {name: "Denied"}), (error) => error.code === "permission-denied");
  await updateCustomerTransaction(db, f.repB, f.companyId, f.customerId, {name: "New manager"});
  await assert.rejects(confirmInvoiceTransaction(db, f.repA, f.companyId, "stale"), (error) => error.code === "permission-denied");
  await f.draft("new", f.repB);
  await confirmInvoiceTransaction(db, f.repB, f.companyId, "new");
  assert.equal((await f.path("invoices", "new").get()).data().salesRepId, f.repB);
  assert.equal((await f.customer()).currentBalance, 100);
});
test("new collector pays historical invoices without reassigning them, using only the new rep cash", async () => {
  const f = await fixture();
  await f.draft("old", f.repA);
  await confirmInvoiceTransaction(db, f.repA, f.companyId, "old");
  const oldLedger = await f.rows("financial_ledger_entries");
  await f.transfer(f.repB);
  await assert.rejects(createReceiptTransaction(db, f.repA, f.companyId, "denied-receipt", {customerId: f.customerId, amount: 20, paymentMethod: "cash", receiptDate: Date.now()}), (error) => error.code === "permission-denied");
  const posted = await createReceiptTransaction(db, f.repB, f.companyId, "new-receipt", {customerId: f.customerId, amount: 60, paymentMethod: "cash", receiptDate: Date.now()});
  const receipt = (await f.path("receipts", posted.receiptId).get()).data();
  assert.deepEqual(receipt.invoiceAllocations, {old: 60});
  assert.equal(receipt.salesRepId, f.repB);
  assert.equal(receipt.createdByUid, f.repB);
  const collections = (await f.rows("financial_ledger_entries")).filter((entry) => entry.sourceId === posted.receiptId);
  assert.ok(collections.every((entry) => entry.salesRepId === f.repB && entry.debitAccountKey === `rep_cash:${f.repB}`));
  assert.equal((await f.path("cash_balances", `rep_${f.repB}`).get()).data().amount, 60);
  assert.equal((await f.path("cash_balances", `rep_${f.repA}`).get()).exists, false);
  const invoice = (await f.path("invoices", "old").get()).data();
  assert.equal(invoice.salesRepId, f.repA);
  assert.equal(invoice.paidAmount, 60);
  assert.equal(invoice.remainingAmount, 40);
  for (const entry of oldLedger) assert.deepEqual((await f.path("financial_ledger_entries", entry.id).get()).data(), entry);
  const {runHistoricalLedgerBackfill} = require("../lib/maintenance/rebuild_financial_ledger");
  const report = await runHistoricalLedgerBackfill({projectId: app.options.projectId, companyId: f.companyId,
    fromText: "", toText: "", apply: false, confirmProject: "", confirmCompany: "", pageSize: 100, maxWrites: 500}, db);
  assert.equal(report.safeForControlledBackfill, true, JSON.stringify(report.anomalies));
  await cancelReceiptTransaction(db, f.admin, f.companyId, posted.receiptId, "Incorrect payment");
  assert.equal((await f.path("invoices", "old").get()).data().paidAmount, 0);
  assert.equal((await f.path("cash_balances", `rep_${f.repB}`).get()).data().amount, 0);
});
test("returns require both current customer assignment and original invoice ownership; Admin handles cross-rep history", async () => {
  const f = await fixture();
  await f.draft("old", f.repA);
  await confirmInvoiceTransaction(db, f.repA, f.companyId, "old");
  await f.transfer(f.repB);
  const input = {originalInvoiceId: "old", items: [{originalInvoiceItemId: "old:line:line", returnedQuantity: 1}], refundType: "credit_customer_balance", reason: "Returned", returnDate: Timestamp.now()};
  for (const uid of [f.repA, f.repB]) await assert.rejects(confirmSalesReturnTransaction(db, uid, f.companyId, `denied-${uid}`, input), (error) => error.code === "permission-denied");
  await confirmSalesReturnTransaction(db, f.admin, f.companyId, "admin-return", input);
  assert.equal((await f.path("sales_returns", "admin-return").get()).data().salesRepId, f.repA);
  await f.draft("new", f.repB);
  await confirmInvoiceTransaction(db, f.repB, f.companyId, "new");
  await confirmSalesReturnTransaction(db, f.repB, f.companyId, "new-return", {...input, originalInvoiceId: "new", items: [{originalInvoiceItemId: "new:line:line", returnedQuantity: 1}]});
});

test("Admin collections after transfer are visible to the current customer assignee, not the historical invoice rep", async () => {
  for (const targetRole of ["rep", "admin"]) {
    const f = await fixture();
    await f.draft("old", f.repA);
    await confirmInvoiceTransaction(db, f.repA, f.companyId, "old");
    const target = targetRole === "rep" ? f.repB : f.admin;
    await f.transfer(target);
    const posted = await createReceiptTransaction(db, f.admin, f.companyId, "admin-new-collection", {
      customerId: f.customerId, amount: 20, paymentMethod: "cash", receiptDate: Date.now()});
    assert.equal((await f.path("receipts", posted.receiptId).get()).data().salesRepId, target);
    assert.equal((await f.path("cash_balances", "company_cash").get()).data().amount, 20);
    assert.equal((await f.path("invoices", "old").get()).data().salesRepId, f.repA);
  }
});
async function transient(operation) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {return await operation();} catch (error) {
      if (!String(error.message).includes("Transaction is invalid or closed") || attempt === 2) throw error;
    }
  }
}
test("concurrent different transfers use revision compare-and-set; one wins without rewriting history", async () => {
  const f = await fixture();
  const input = await f.request(f.repB);
  const results = await Promise.allSettled([transient(() => reassignCustomerTransaction(db, f.admin, input)),
    transient(() => reassignCustomerTransaction(db, f.admin, {...input, assignedToUid: f.admin, idempotencyKey: "competing-transfer"}))]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal((await f.customer()).assignmentRevision, 1);
  assert.equal((await f.rows("customer_assignment_events")).length, 1);
});

test("original sales KPIs survive transfer; new collections are not sales and global debt/statement stay accurate", async () => {
  const f = await fixture();
  const {getDashboardSnapshot} = require("../lib/trusted/dashboard_reporting");
  const dashboard = (uid) => getDashboardSnapshot.run({auth: {uid}, data: {companyId: f.companyId, from: 0, to: Date.now() + 1000}});
  await f.draft("original-sale", f.repA);
  await confirmInvoiceTransaction(db, f.repA, f.companyId, "original-sale");
  assert.equal((await dashboard(f.repA)).totalSales, 100);
  await f.transfer(f.repB);
  assert.equal((await dashboard(f.repA)).totalSales, 100);
  assert.equal((await dashboard(f.repA)).customerCount, 0);
  assert.equal((await dashboard(f.repB)).totalSales, 0);
  assert.equal((await dashboard(f.repB)).totalReceivables, 100);
  for (const [key, amount] of [["payment-1", 40], ["payment-2", 30]]) {
    await createReceiptTransaction(db, f.repB, f.companyId, key, {customerId: f.customerId, amount, paymentMethod: "cash", receiptDate: Date.now()});
  }
  const collector = await dashboard(f.repB);
  assert.equal(collector.totalSales, 0);
  assert.equal(collector.salesByRepSummary[0].receiptsCollected, 70);
  assert.equal(collector.repCashOutstanding, 70);
  assert.equal(collector.totalReceivables, 30);
  assert.equal((await dashboard(f.repA)).totalSales, 100);
  await f.draft("new-sale", f.repB);
  await confirmInvoiceTransaction(db, f.repB, f.companyId, "new-sale");
  assert.equal((await dashboard(f.repB)).totalSales, 100);
  assert.equal((await dashboard(f.repA)).totalSales, 100);
  const transactions = await f.rows("customer_transactions");
  assert.equal(transactions.reduce((sum, entry) => sum + entry.debitAmount - entry.creditAmount, 0), 130);
  assert.equal((await f.customer()).currentBalance, 130);
  const {getReceivableBalances, reconcileFinancialLedgerAccountActivity, ACCOUNT_ACTIVITY_PROJECTION_VERSION} = require("../lib/trusted/financial_ledger_account_reporting");
  for (const entry of await f.rows("financial_ledger_entries")) await reconcileFinancialLedgerAccountActivity(db, f.companyId, entry.id);
  await f.path("financial_ledger_account_activity_metadata", "current").set({status: "ready", projectionVersion: ACCOUNT_ACTIVITY_PROJECTION_VERSION});
  const request = {data: {companyId: f.companyId, customerIds: [f.customerId], atExclusive: Date.now() + 1000}};
  const projected = await getReceivableBalances.run({...request, auth: {uid: f.repB}});
  assert.equal(projected.balances[0].balance, 130);
  await assert.rejects(getReceivableBalances.run({...request, auth: {uid: f.repA}}), (error) => error.code === "permission-denied");
});

test("migration CLI dry-run, apply, repeat and rollback preserve every original customer field", async () => {
  const f = await fixture({legacy: true});
  const {execFileSync} = require("node:child_process");
  const {join} = require("node:path");
  const script = join(__dirname, "../scripts/backfill_customer_assignment.js");
  const base = [script, `--project=${app.options.projectId}`, `--company=${f.companyId}`];
  const run = (...args) => execFileSync(process.execPath, [...base, ...args], {env: process.env, encoding: "utf8"});
  const apply = ["--apply", `--confirm-project=${app.options.projectId}`, `--confirm-company=${f.companyId}`];
  const before = await f.customer();
  assert.ok(run().includes('"planned": 1'));
  assert.deepEqual(await f.customer(), before);
  run(...apply);
  const migrated = await f.customer();
  assert.equal(migrated.assignedToUid, before.createdByUid);
  run(...apply);
  assert.deepEqual(await f.customer(), migrated);
  run("--rollback");
  assert.deepEqual(await f.customer(), migrated);
  run("--rollback", ...apply);
  assert.deepEqual(await f.customer(), before);
  run("--rollback", ...apply);
  assert.deepEqual(await f.customer(), before);
});

test("migration update-time guard cannot overwrite a real transfer", async () => {
  const f = await fixture({legacy: true});
  const snapshot = await f.path("customers", f.customerId).get();
  const plan = legacyAssignmentUpdate(snapshot.data(), (await db.doc(`users/${f.repA}`).get()).data(), f.companyId);
  await f.transfer(f.repB);
  await assert.rejects(snapshot.ref.update(plan, {lastUpdateTime: snapshot.updateTime}));
  assert.equal((await f.customer()).assignedToUid, f.repB);
  assert.equal((await f.customer()).assignmentRevision, 1);
});

test("collection racing transfer either posts before transfer or is denied, with consistent debt and cash", async () => {
  const f = await fixture();
  await f.draft("old", f.repA);
  await confirmInvoiceTransaction(db, f.repA, f.companyId, "old");
  const [transfer, collection] = await Promise.allSettled([transient(() => f.transfer(f.repB)),
    transient(() => createReceiptTransaction(db, f.repA, f.companyId, "racing-collection", {
      customerId: f.customerId, amount: 30, paymentMethod: "cash", receiptDate: Date.now()}))]);
  assert.equal(transfer.status, "fulfilled");
  assert.equal((await f.customer()).assignedToUid, f.repB);
  const collected = collection.status === "fulfilled" ? 30 : 0;
  if (!collected) assert.equal(collection.reason.code, "permission-denied");
  assert.equal((await f.customer()).currentBalance, 100 - collected);
  assert.equal((await f.path("invoices", "old").get()).data().paidAmount, collected);
  assert.equal((await f.path("cash_balances", `rep_${f.repA}`).get()).data()?.amount ?? 0, collected);
});
