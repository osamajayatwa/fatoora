"use strict";
const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
const {before, after, test} = require("node:test");
const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {collection, query, where, orderBy, documentId, limit, startAfter,
  getDocs, getAggregateFromServer, count, sum} = require("firebase/firestore");
const {documentSearchFields, normalizeSearchText} = require("../shared/search_keywords");
const {reconcileOperationalSearchFields} = require("../lib/trusted/operational_search_projection");

const projectId = "fatoora-phase2-search-test";
const company = "default_company";
const path = (name) => `companies/${company}/${name}`;
let environment;
let app;
let db;

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "These tests require the local Firestore emulator");
  environment = await initializeTestEnvironment({projectId,
    firestore: {rules: readFileSync(join(__dirname, "..", "..", "firestore.rules"), "utf8")}});
  await environment.clearFirestore();
  app = initializeApp({projectId}, "phase2-search");
  db = getFirestore(app);
  const batch = db.batch();
  for (const [uid, role] of [["rep-a", "sales_rep"], ["rep-b", "sales_rep"], ["admin", "admin"]]) {
    batch.set(db.doc(`users/${uid}`), {uid, role, companyId: company, active: true, approvalStatus: "approved"});
  }
  // Matching rows lie beyond the first unfiltered page. A client-side filter
  // over loaded rows would miss all of them.
  for (let index = 0; index < 50; index++) {
    const target = index >= 45;
    const invoice = {companyId: company, salesRepId: "rep-a", invoiceNumber: `INV-2026-${index}`,
      customerSnapshot: {name: target ? "أَحمد   عبد الرحمن" : "Other Customer"},
      invoiceStatus: index % 2 ? "confirmed" : "draft", invoiceType: "regular",
      invoiceDate: Timestamp.fromMillis(100000 - index * 1000)};
    batch.set(db.doc(`${path("invoices")}/invoice-${index}`), {...invoice, ...documentSearchFields("invoices", invoice)});
    const custody = {companyId: company, salesRepId: "rep-a", itemId: `item-${index}`,
      itemNameSnapshot: target ? "Water   Pump" : "Other Item", modelSnapshot: target ? "WP-12" : "OTHER",
      quantity: 4, updatedAt: Timestamp.fromMillis(100000 - index * 1000)};
    batch.set(db.doc(`${path("rep_inventory_balances")}/balance-${index}`),
      {...custody, ...documentSearchFields("rep_inventory_balances", custody)});
    const item = {name: custody.itemNameSnapshot, code: custody.modelSnapshot, deleted: false, active: true,
      createdAt: custody.updatedAt, currentStock: 30, price: index};
    batch.set(db.doc(`items/item-${index}`), {...item, ...documentSearchFields("items", item)});
  }
  const other = {companyId: company, salesRepId: "rep-b", invoiceNumber: "INV-OTHER", customerSnapshot: {name: "أحمد عبد الرحمن"},
    invoiceDate: Timestamp.fromMillis(100000)};
  batch.set(db.doc(`${path("invoices")}/other-owner`), {...other, ...documentSearchFields("invoices", other)});
  for (const [id, owner, quantity] of [["other-owner", "rep-b", 8], ["zero", "rep-a", 0]]) {
    const balance = {companyId: company, salesRepId: owner, itemNameSnapshot: "Water Pump", modelSnapshot: "WP-12",
      quantity, updatedAt: Timestamp.fromMillis(100000)};
    batch.set(db.doc(`${path("rep_inventory_balances")}/${id}`), {...balance, ...documentSearchFields("rep_inventory_balances", balance)});
  }
  await batch.commit();
});
after(async () => {
  if (environment) await environment.cleanup();
  if (app) await deleteApp(app);
});

test("Arabic multi-word invoice search paginates across all owned results and preserves status filters", async () => {
  const client = environment.authenticatedContext("rep-a").firestore();
  const base = collection(client, path("invoices"));
  const filters = [where("salesRepId", "==", "rep-a"),
    where("searchKeywords", "array-contains", normalizeSearchText("  احمد   عبد ")),
    orderBy("invoiceDate", "desc"), orderBy(documentId(), "desc")];
  const first = await getDocs(query(base, ...filters, limit(2)));
  const second = await getDocs(query(base, ...filters, startAfter(first.docs.at(-1)), limit(2)));
  const third = await getDocs(query(base, ...filters, startAfter(second.docs.at(-1)), limit(2)));
  assert.deepEqual([...first.docs, ...second.docs, ...third.docs].map((doc) => doc.id),
    ["invoice-45", "invoice-46", "invoice-47", "invoice-48", "invoice-49"]);
  const confirmed = await getDocs(query(base, ...filters, where("invoiceStatus", "==", "confirmed")));
  assert.equal(confirmed.size, 3);
  const number = await getDocs(query(base, where("salesRepId", "==", "rep-a"),
    where("searchKeywords", "array-contains", normalizeSearchText("INV ۲۰۲۶ ۴۹"))));
  assert.equal(number.docs[0].id, "invoice-49");
  await assertFails(getDocs(query(base, where("salesRepId", "==", "rep-b"), filters[1])));
  await assertFails(getDocs(query(base, filters[1])));
});

test("warehouse and custody searches page through the authorized dataset using the correct quantity", async () => {
  const rep = environment.authenticatedContext("rep-a").firestore();
  const base = collection(rep, path("rep_inventory_balances"));
  const filters = [where("salesRepId", "==", "rep-a"), where("hasStock", "==", true),
    where("searchKeywords", "array-contains", normalizeSearchText("  Water   Pu ")),
    orderBy("updatedAt", "desc"), orderBy(documentId(), "desc")];
  const first = await getDocs(query(base, ...filters, limit(2)));
  const rest = await getDocs(query(base, ...filters, startAfter(first.docs.at(-1)), limit(36)));
  assert.equal(first.size + rest.size, 5);
  assert.ok([...first.docs, ...rest.docs].every((doc) => doc.data().quantity === 4 && doc.data().salesRepId === "rep-a"));
  const code = await getDocs(query(base, ...filters.filter((_, index) => index !== 2),
    where("searchKeywords", "array-contains", normalizeSearchText("WP 12"))));
  assert.equal(code.size, 5);
  const totals = await getAggregateFromServer(query(base, where("salesRepId", "==", "rep-a"), where("quantity", ">", 0)),
    {itemCount: count(), totalQuantity: sum("quantity")});
  assert.deepEqual(totals.data(), {itemCount: 50, totalQuantity: 200});
  await assertFails(getDocs(query(base, where("salesRepId", "==", "rep-b"), where("hasStock", "==", true))));
  await assertFails(getDocs(query(base, where("hasStock", "==", true))));
  const admin = environment.authenticatedContext("admin").firestore();
  const warehouse = collection(admin, "items");
  const itemFilters = [where("deleted", "==", false), where("active", "==", true),
    where("searchKeywords", "array-contains", normalizeSearchText("water pump")),
    orderBy("createdAt", "desc"), orderBy(documentId(), "desc")];
  const warehouseFirst = await getDocs(query(warehouse, ...itemFilters, limit(2)));
  const warehouseRest = await getDocs(query(warehouse, ...itemFilters, startAfter(warehouseFirst.docs.at(-1)), limit(36)));
  assert.equal(warehouseFirst.size + warehouseRest.size, 5);
  assert.ok([...warehouseFirst.docs, ...warehouseRest.docs].every((doc) => doc.data().currentStock === 30));
});

test("search projection repairs current metadata idempotently without changing posting fields or ordering", async () => {
  for (const name of ["invoices", "rep_inventory_balances"]) {
    const ref = db.doc(`${path(name)}/projection`);
    const fields = {companyId: company, salesRepId: "rep-a", itemNameSnapshot: "Old Item", modelSnapshot: "OLD-1", quantity: 9,
      invoiceNumber: "INV-OLD", customerSnapshot: {name: "Old Customer"},
      financialPosted: true, inventoryPosted: true, grandTotal: 321, updatedAt: Timestamp.fromMillis(12345)};
    await ref.set(fields);
    // A delayed event must index the latest persisted values, not its old event snapshot.
    await ref.update({itemNameSnapshot: "أَحمد   عبد", customerSnapshot: {name: "أَحمد   عبد"}, quantity: 0});
    const before = (await ref.get()).data();
    await reconcileOperationalSearchFields(db, ref.path, name);
    const after = await ref.get();
    const {searchKeywords, hasStock, ...businessFields} = after.data();
    assert.deepEqual(businessFields, before);
    assert.ok(searchKeywords.includes("احمد عبد"));
    if (name === "rep_inventory_balances") assert.equal(hasStock, false);
    await reconcileOperationalSearchFields(db, ref.path, name);
    assert.ok((await ref.get()).updateTime.isEqual(after.updateTime));
  }
});
