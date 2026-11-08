"use strict";
// Real Auth -> callable HTTP -> trusted transaction -> client Rules -> triggers.
// This suite refuses cloud endpoints and never loads a production credential.
const assert = require("node:assert/strict"), {test, after} = require("node:test");
const {randomUUID} = require("node:crypto"), fs = require("node:fs"), path = require("node:path");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore"), {getAuth} = require("firebase-admin/auth");
const clientApp = require("firebase/app"), clientAuth = require("firebase/auth"), sdk = require("firebase/firestore");
const PROJECT = "demo-fatoora-release-test", clients = [], results = [];
for (const key of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FUNCTIONS_EMULATOR_HOST"]) {
  assert.match(process.env[key] || "", /^127\.0\.0\.1:\d+$/, `${key}: dedicated loopback emulator required`);
}
const app = initializeApp({projectId: PROJECT}), db = getFirestore(app), auth = getAuth(app);
after(async () => {
  await Promise.all(clients.map(a => clientApp.deleteApp(a)));
  await deleteApp(app);
  const folder = path.join(__dirname, "../../build/reassignment-release-evidence"); fs.mkdirSync(folder, {recursive: true});
  fs.writeFileSync(path.join(folder, "e2e-accounting.json"), JSON.stringify({project: PROJECT, syntheticOnly: true, results}, null, 2) + "\n");
});
async function fixture() {
  const companyId = `release-${randomUUID()}`, users = {}, tokens = {};
  for (const [name, role] of [["admin", "admin"], ["a", "sales_rep"], ["b", "sales_rep"], ["inactive", "sales_rep"], ["foreign", "sales_rep"]]) {
    const uid = `${companyId}-${name}`, email = `${uid}@synthetic.invalid`, password = `Emulator-only-${randomUUID()}`;
    await auth.createUser({uid, email, password});
    await db.doc(`users/${uid}`).set({uid, name, role, email, companyId: name === "foreign" ? "other-company" : companyId, active: true, approvalStatus: "approved"});
    const a = clientApp.initializeApp({projectId: PROJECT, apiKey: "synthetic-emulator", authDomain: `${PROJECT}.firebaseapp.com`}, uid); clients.push(a);
    const ca = clientAuth.getAuth(a); clientAuth.connectAuthEmulator(ca, `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, {disableWarnings: true});
    const signed = await clientAuth.signInWithEmailAndPassword(ca, email, password); tokens[name] = await signed.user.getIdToken();
    const store = sdk.getFirestore(a), [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(":");
    sdk.connectFirestoreEmulator(store, host, Number(port)); users[name] = {uid, db: store};
  }
  const ref = (collection, id) => db.doc(`companies/${companyId}/${collection}/${id}`);
  const clientRef = (name, collection, id) => sdk.doc(users[name].db, "companies", companyId, collection, id);
  const call = async (name, functionName, data = {}, expectedError) => {
    const response = await fetch(`http://${process.env.FUNCTIONS_EMULATOR_HOST}/${PROJECT}/us-central1/${functionName}`, {
      method: "POST", headers: {"content-type": "application/json", ...(name ? {authorization: `Bearer ${tokens[name]}`} : {})},
      body: JSON.stringify({data: {companyId, ...data}}), signal: AbortSignal.timeout(45000),
    });
    const body = await response.json();
    if (expectedError) { assert.equal(body.error?.status, expectedError, JSON.stringify(body)); return; }
    assert.equal(response.status, 200, `${functionName}: ${JSON.stringify(body)}`); return body.result;
  };
  const customer = async (owner, key) => (await call(owner, "createCustomer", {idempotencyKey: `customer-${key}`, name: "Synthetic release customer", active: true})).customerId;
  let sequence = 0;
  const draft = async (owner, id, customerId, {price = 10, quantity = 3, tax = 16, discount = 3, paid = 0, item = null} = {}) => {
    const uid = users[owner].uid, admin = owner === "admin", subtotal = price * quantity, grandTotal = money((subtotal - discount) * (1 + tax / 100));
    await sdk.setDoc(clientRef(owner, "invoices", id), {id, companyId, invoiceNumber: `INV-2026-${String(++sequence).padStart(6, "0")}`,
      invoiceType: "regular", invoiceStatus: "draft", paymentType: "credit", paymentStatus: "unpaid",
      hasReceivedPayment: paid > 0, invoiceDate: new Date("2026-11-06T09:00:00Z"), dueDate: new Date("2026-11-30T09:00:00Z"),
      createdAt: sdk.serverTimestamp(), updatedAt: sdk.serverTimestamp(), createdByUid: uid, createdByName: owner,
      createdByRole: admin ? "admin" : "sales_rep", salesRepId: uid, salesRepName: owner, customerId,
      customerSnapshot: {id: customerId, name: "Synthetic release customer"},
      items: [{lineId: "line", lineType: item ? "catalog" : "custom", itemId: item, itemName: "Synthetic item", description: "Synthetic service", unit: "pcs",
        quantity, unitPrice: price, discount, taxPercent: tax}], subtotal, totalDiscount: discount, totalTax: (subtotal - discount) * tax / 100,
      grandTotal, paidAmount: paid, remainingAmount: grandTotal - paid, returnStatus: "none", returnedTotal: 0,
      returnedSubtotal: 0, returnedDiscount: 0, returnedTax: 0, returnedReceivableAmount: 0, customerCreditAmount: 0,
      cashRefundAmount: 0, returnInvoiceIds: [], latestReturnAt: null, receiptIds: [], lastReceiptId: "", isLocked: false,
      financialPosted: false, financialPostedAt: null, financialPostedByUid: "", financialPostedByName: "",
      customerTransactionIds: [], cashMovementIds: [], inventoryPosted: false, inventoryPostedAt: null,
      inventoryPostedByUid: "", inventoryPostedByName: "", inventoryMovementIds: [],
      stockSourceType: admin ? "companyWarehouse" : "salesRep", stockSourceId: admin ? "default_warehouse" : uid,
      stockSourceSalesRepId: admin ? "" : uid, searchKeywords: ["synthetic"], invoiceNumberLower: id, customerNameLower: "synthetic"});
  };
  const dashboard = name => call(name, "getDashboardSnapshot", {from: 0, to: Date.now()});
  return {companyId, users, ref, clientRef, call, customer, draft, dashboard};
}
const denied = promise => assert.rejects(promise, error => error.code === "permission-denied");
const money = n => Math.round(n * 1000) / 1000;
async function ledger(f, expected) {
  for (let attempt = 0; attempt < 80; attempt++) {
    const summary = await f.call("admin", "getFinancialLedgerSummary", {from: 0, to: Date.now()});
    if (Object.entries(expected).every(([key, value]) => summary[key] === value)) return summary;
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  throw Error("Reporting triggers did not reconcile before the acceptance deadline");
}

test("HTTP reassignment, historical reads, collection, partial refund, cash ownership and revocation", {timeout: 180000}, async () => {
  const f = await fixture(), customerId = await f.customer("a", randomUUID());
  const item = `${f.companyId}-item`, uidA = f.users.a.uid, uidB = f.users.b.uid;
  await db.doc(`items/${item}`).set({id: item, companyId: f.companyId, name: "Synthetic item", code: "synthetic", unit: "pcs", active: true, deleted: false, trackStock: true, currentStock: 20, costPrice: 2});
  await f.ref("rep_inventory_balances", `${uidA}_${item}`).set({id: `${uidA}_${item}`, companyId: f.companyId, salesRepId: uidA, itemId: item, quantity: 10});
  await f.draft("a", "old", customerId, {item}); await f.draft("a", "stale", customerId, {item});
  await f.call("a", "confirmInvoice", {invoiceId: "old"});
  const before = (await f.ref("invoices", "old").get()).data();
  const transfer = {customerId, assignedToUid: uidB, expectedAssignedToUid: uidA, expectedAssignmentRevision: 0,
    idempotencyKey: `transfer-${randomUUID()}`, reason: "Synthetic release acceptance"};
  await f.call("a", "reassignCustomer", transfer, "PERMISSION_DENIED");
  await f.call("admin", "reassignCustomer", transfer);
  assert.deepEqual((await f.ref("invoices", "old").get()).data(), before);
  await denied(sdk.getDocFromServer(f.clientRef("a", "customers", customerId)));
  await sdk.getDocFromServer(f.clientRef("b", "invoices", "old"));
  await denied(sdk.getDocFromServer(f.clientRef("b", "invoices", "stale")));
  await denied(sdk.getDocFromServer(f.clientRef("foreign", "invoices", "old")));
  await f.call("a", "confirmInvoice", {invoiceId: "stale"}, "PERMISSION_DENIED");
  const transactions = name => sdk.query(sdk.collection(f.users[name].db, "companies", f.companyId, "customer_transactions"), sdk.where("customerId", "==", customerId));
  await denied(sdk.getDocsFromServer(transactions("a")));
  assert.ok((await sdk.getDocsFromServer(transactions("b"))).size > 0);
  const receipt = await f.call("b", "createReceipt", {idempotencyKey: `collection-${randomUUID()}`, customerId, amount: 31.32, paymentMethod: "cash", receiptDate: "2026-11-07T09:00:00Z"});
  assert.deepEqual((await f.ref("receipts", receipt.receiptId).get()).data().invoiceAllocations, {old: 31.32});
  await f.draft("b", "new", customerId, {price: 15, quantity: 1, discount: 0}); await f.call("b", "confirmInvoice", {invoiceId: "new"});
  const input = {idempotencyKey: `return-${randomUUID()}`, originalInvoiceId: "old", refundType: "cash_refund", reason: "Synthetic refund",
    returnDate: "2026-11-07T10:00:00Z", items: [{originalInvoiceItemId: "old:line:line", returnedQuantity: 1}]};
  await f.call("b", "confirmSalesReturn", input, "PERMISSION_DENIED");
  const posted = await f.call("admin", "confirmSalesReturn", input);
  assert.equal((await f.call("admin", "confirmSalesReturn", input)).alreadyPosted, true);
  const returned = (await f.ref("sales_returns", posted.returnId).get()).data();
  assert.equal(returned.salesRepId, uidA); assert.equal(returned.cashRefundAmount, 10.44);
  assert.equal((await f.ref("cash_balances", `rep_${uidB}`).get()).data().amount, 20.88);
  assert.equal((await f.ref("rep_inventory_balances", `${uidA}_${item}`).get()).data().quantity, 8);
  assert.equal((await db.doc(`items/${item}`).get()).data().currentStock, 20);
  const history = sdk.query(sdk.collection(f.users.b.db, "companies", f.companyId, "invoices"), sdk.and(
    sdk.where("customerId", "==", customerId), sdk.or(sdk.where("salesRepId", "==", uidB), sdk.where("financialPosted", "==", true))),
    sdk.orderBy("invoiceDate"), sdk.orderBy("__name__"));
  assert.equal((await sdk.getDocsFromServer(history)).size, 2);
  const page = await sdk.getDocsFromServer(sdk.query(history, sdk.limit(1)));
  const dashboard = await f.dashboard("admin"); assert.equal(dashboard.totalSales, 38.28);
  assert.equal((await f.dashboard("a")).totalSales, 20.88); assert.equal((await f.dashboard("b")).totalSales, 17.4);
  const summary = await ledger(f, {metricSales: 38.28, metricRepCashOut: 10.44, metricReceivables: 17.4}); assert.equal(summary.metricRepCashOut, 10.44); assert.equal(summary.metricReceivables, 17.4);
  const customer = (await f.ref("customers", customerId).get()).data(); assert.equal(customer.currentBalance, 17.4);
  const refund = (await f.ref("financial_ledger_entries", `sales_return_${posted.returnId}_cash_refund`).get()).data();
  assert.equal(refund.salesRepId, uidB); assert.equal(refund.metricSales, 0);
  await f.call("admin", "reassignCustomer", {...transfer, assignedToUid: f.users.admin.uid, expectedAssignedToUid: uidB,
    expectedAssignmentRevision: 1, idempotencyKey: `transfer-${randomUUID()}`});
  await denied(sdk.getDocsFromServer(sdk.query(history, sdk.startAfter(page.docs[0]))));
  await denied(sdk.getDocFromServer(f.clientRef("b", "invoices", "old")));
  await f.call(null, "getDashboardSnapshot", {from: 0, to: Date.now()}, "UNAUTHENTICATED");
  results.push({scenario: "transfer-collection-refund", companyNetBilledIncludingTax: 38.28, sellerA: 20.88, sellerB: 17.4,
    cashHolder: "collector-B", cash: 20.88, receivable: 17.4, refund: 10.44, originalCustodyQuantity: 8});
});

test("Admin, active and inactive seller reconciliation keeps gross, returns, tax, collections and debt distinct", {timeout: 180000}, async () => {
  const f = await fixture(), documents = [];
  for (const [owner, price, quantity, paid] of [["admin", 50, 1, 58], ["a", 100, 1, 0], ["inactive", 12.5, 2, 10]]) {
    const customerId = await f.customer(owner, randomUUID());
    await f.draft(owner, owner, customerId, {price, quantity, paid, discount: 0});
    await f.call(owner, "confirmInvoice", {invoiceId: owner}); documents.push(f.ref("invoices", owner));
  }
  await db.doc(`users/${f.users.inactive.uid}`).update({active: false});
  await f.call("inactive", "getDashboardSnapshot", {from: 0, to: Date.now()}, "PERMISSION_DENIED");
  await f.call("admin", "confirmSalesReturn", {idempotencyKey: `return-${randomUUID()}`, originalInvoiceId: "inactive",
    refundType: "cash_refund", reason: "Synthetic inactive seller return", returnDate: "2026-11-07T10:00:00Z",
    items: [{originalInvoiceItemId: "inactive:line:line", returnedQuantity: 1}]});
  const invoices = await Promise.all(documents.map(async ref => (await ref.get()).data()));
  const returns = (await db.collection(`companies/${f.companyId}/sales_returns`).get()).docs.map(d => d.data());
  const billed = money(invoices.reduce((n, i) => n + i.grandTotal, 0)), returned = money(returns.reduce((n, r) => n + r.grandTotal, 0));
  const tax = money(invoices.reduce((n, i) => n + i.totalTax, 0) - returns.reduce((n, r) => n + r.totalTax, 0));
  const sellerNet = Object.fromEntries(["admin", "a", "inactive"].map(name => [name, money(
    invoices.filter(i => i.salesRepId === f.users[name].uid).reduce((n, i) => n + i.grandTotal, 0) -
    returns.filter(r => r.salesRepId === f.users[name].uid).reduce((n, r) => n + r.grandTotal, 0))]));
  const dashboard = await f.dashboard("admin");
  assert.deepEqual(sellerNet, {admin: 58, a: 116, inactive: 14.5});
  assert.equal(dashboard.totalSales, money(Object.values(sellerNet).reduce((n, amount) => n + amount, 0)));
  assert.equal(billed, 203); assert.equal(returned, 14.5); assert.equal(tax, 26);
  assert.equal(dashboard.totalSales, 188.5); assert.equal(money(dashboard.totalSales - tax), 162.5);
  assert.equal(dashboard.totalReceivables, 120.5); assert.equal(dashboard.companyCash, 58); assert.equal(dashboard.repCashOutstanding, 10);
  assert.equal(dashboard.receiptCount, 0); // Initial invoice cash is a collection, not a receipt or additional sale.
  assert.equal(money(dashboard.salesByRepSummary.reduce((n, row) => n + row.totalSales, 0)), 116);
  const summary = await ledger(f, {metricSales: 188.5, metricReceivables: 120.5}); assert.equal(summary.metricReceivables, 120.5);
  for (const invoice of invoices) assert.equal(invoice.salesRepId, f.users[invoice.id].uid);
  results.push({scenario: "all-seller-categories", grossBilledIncludingTax: billed, returnsIncludingTax: returned,
    netBilledIncludingTax: dashboard.totalSales, netTax: tax, netSalesExcludingTax: 162.5,
    initialCollections: 68, receiptCollections: 0, receivables: 120.5, sellerNet, displayedActiveRepSubtotal: 116});
});
