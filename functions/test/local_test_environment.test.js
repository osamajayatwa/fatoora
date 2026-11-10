"use strict";
const assert = require("node:assert/strict");
const {before, after, test} = require("node:test");
const {readFileSync, existsSync} = require("node:fs");
const {join} = require("node:path");
const {randomBytes} = require("node:crypto");
const tools = require("../scripts/local_test_environment");
const sample = (id = "test-item") => ({id, data: {id, companyId: "default_company", code: `SKU-${id}`, name: "Test pump / مضخة",
  description: "Technical definition", unit: "pcs", price: 12.345, taxRate: 16, active: true, deleted: false,
  specifications: {power: "1 kW", material: "steel"}, currentStock: 55, openingStock: 70, costPrice: 9.1,
  createdBy: "production-user", customerId: "private-customer", creationRequest: {openingStock: 70}, lastStockMovementId: "history"}});
const syntheticBundle = tools.sanitizeCatalog([sample()]);
const actualPath = join(__dirname, "../../build/local-test/catalog.json");
const catalog = process.env.FATOORA_SYNTHETIC_TESTS_ONLY !== "1" && existsSync(actualPath) ? JSON.parse(readFileSync(actualPath, "utf8")) : syntheticBundle;

test("catalog copy preserves IDs, definitions and selling prices while removing inventory, costs and history", () => {
  const original = sample(), before = JSON.stringify(original), bundle = tools.sanitizeCatalog([original]);
  assert.equal(JSON.stringify(original), before);
  const row = bundle.items[0], item = tools.targetItem(row);
  assert.equal(row.id, original.id);
  for (const field of ["name", "code", "price", "taxRate", "specifications"]) assert.deepEqual(item[field], original.data[field]);
  for (const field of ["currentStock", "openingStock", "minStock", "costPrice", "inventoryValue"]) assert.equal(item[field], 0);
  for (const field of ["createdBy", "customerId", "creationRequest", "lastStockMovementId"]) assert.equal(field in row.data, false);
  assert.equal(item.createdBy, tools.ADMIN_UID);
  assert.equal(item.stockStatus, "out");
});
test("catalog sanitization is deterministic and supports the existing unowned legacy root catalog", () => {
  const legacy = sample("legacy"); delete legacy.data.companyId;
  const foreign = sample("foreign"); foreign.data.companyId = "unrelated";
  assert.deepEqual(tools.sanitizeCatalog([legacy, sample(), foreign]), tools.sanitizeCatalog([sample(), legacy]));
});
for (const [field, bad] of [["id", "wrong-id"], ["companyId", null], ["price", "12.345"], ["price", Infinity],
  ["price", -1], ["active", "true"], ["taxRate", 101], ["name", ""]]) {
  test(`catalog rejects malformed ${field}`, () => {
    const row = sample(); row.data[field] = bad;
    assert.throws(() => tools.sanitizeCatalog([row]), {code: "TEST_SETUP_BLOCKED"});
  });
}
test("catalog rejects duplicate IDs and sensitive nested specifications", () => {
  assert.throws(() => tools.sanitizeCatalog([sample(), sample()]), {code: "TEST_SETUP_BLOCKED"});
  const row = sample(); row.data.specifications.supplierCost = 123;
  assert.throws(() => tools.sanitizeCatalog([row]), {code: "TEST_SETUP_BLOCKED"});
});
test("bootstrap refuses cloud projects, missing emulators, non-loopback hosts and mismatched source files", () => {
  for (const [project, fsHost, authHost] of [[tools.PRODUCTION, "127.0.0.1:8080", "127.0.0.1:9099"],
    ["fatoora-staging", "127.0.0.1:8080", "127.0.0.1:9099"], [tools.LOCAL, undefined, "127.0.0.1:9099"],
    [tools.LOCAL, "firestore.googleapis.com:443", "127.0.0.1:9099"]]) {
    assert.throws(() => tools.localContext(project, fsHost, authHost), {code: "TEST_SETUP_BLOCKED"});
  }
  assert.throws(() => tools.validateBundle({...syntheticBundle, sourceCompanyId: "other"}), {code: "TEST_SETUP_BLOCKED"});
});
test("production export only requests whitelisted item definitions at a pinned snapshot, never credentials or history", async () => {
  const fields = Object.fromEntries(Object.entries(syntheticBundle.items[0].data).map(([k, v]) => [k,
    typeof v === "string" ? {stringValue: v} : typeof v === "boolean" ? {booleanValue: v} :
      typeof v === "number" ? {doubleValue: v} : {mapValue: {fields: {power: {stringValue: "1 kW"}, material: {stringValue: "steel"}}}}]));
  const result = await tools.exportCatalog(async (url, body) => {
    assert.match(url, /^https:\/\/firestore\.googleapis\.com\/v1\/projects\/fatoora-6b192\/databases\/\(default\)\/documents:runQuery$/);
    assert.deepEqual(body.structuredQuery.from, [{collectionId: "items"}]);
    for (const excluded of ["costPrice", "currentStock", "createdBy", "creationRequest"]) {
      assert.equal(body.structuredQuery.select.fields.some((f) => f.fieldPath === excluded), false);
    }
    return [{document: {name: "projects/fatoora-6b192/databases/(default)/documents/items/test-item", fields}, readTime: "2026-11-04T00:00:00Z"}];
  });
  assert.deepEqual(result, syntheticBundle);
});

// Keep the existing Firestore-only regression command working. Auth integration
// tests opt in when its emulator is supplied; the bootstrap itself always
// rejects a missing emulator and cannot fall back to a cloud service.
if (process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  tools.localContext(tools.LOCAL, process.env.FIRESTORE_EMULATOR_HOST, process.env.FIREBASE_AUTH_EMULATOR_HOST);
  const {initializeApp, deleteApp} = require("firebase-admin/app"), {getFirestore} = require("firebase-admin/firestore"), {getAuth} = require("firebase-admin/auth");
  const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
  const clientApp = require("firebase/app"), clientAuth = require("firebase/auth"), clientStore = require("firebase/firestore");
  const app = initializeApp({projectId: tools.LOCAL}, "local-environment-verification"), db = getFirestore(app), auth = getAuth(app);
  const password = randomBytes(24).toString("base64url");
  const clients = [];
  let rules, first;
  const seed = () => tools.seedLocalEnvironment({app, firestore: db, auth, bundle: catalog, password});
  before(async () => {
    const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(":");
    rules = await initializeTestEnvironment({projectId: tools.LOCAL, firestore: {host, port: Number(port),
      rules: readFileSync(join(__dirname, "../../firestore.rules"), "utf8")}});
    first = await seed();
  });
  after(async () => {
    for (const c of clients) await clientApp.deleteApp(c);
    await rules?.cleanup(); await deleteApp(app);
  });
  async function login(email, pass) {
    const c = clientApp.initializeApp({projectId: tools.LOCAL, apiKey: "fake-local-api-key", appId: "1:123:web:test"}, `local-${clients.length}`);
    clients.push(c);
    const a = clientAuth.getAuth(c);
    clientAuth.connectAuthEmulator(a, `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, {disableWarnings: true});
    const credential = await clientAuth.signInWithEmailAndPassword(a, email, pass);
    const store = clientStore.getFirestore(c), [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(":");
    clientStore.connectFirestoreEmulator(store, host, Number(port));
    return {store, credential};
  }
  test("emulators: sanitized catalog imports with zero inventory and no business history", async () => {
    assert.equal(first.catalogItems, catalog.items.length);
    assert.equal(first.copiedHistoryDocuments, 0);
    const items = await db.collection("items").get();
    assert.equal(items.size, catalog.items.length);
    const source = new Map(catalog.items.map((i) => [i.id, i.data]));
    for (const doc of items.docs) {
      assert.equal(doc.data().price, source.get(doc.id).price);
      assert.equal(doc.data().name, source.get(doc.id).name);
      for (const field of ["currentStock", "openingStock", "minStock", "costPrice", "inventoryValue"]) assert.equal(doc.data()[field], 0);
    }
    for (const collection of ["customers", "invoices", "cash_movements", "cash_balances", "stock_movements", "financial_ledger_entries"]) {
      assert.equal((await db.collection(`companies/default_company/${collection}`).get()).size, 0);
    }
  });
  test("emulators: admin signs in through real Auth emulator and receives existing full-admin permissions", async () => {
    const {store, credential} = await login(tools.EMAIL, password);
    assert.equal(credential.user.uid, tools.ADMIN_UID);
    assert.equal((await credential.user.getIdTokenResult()).claims.aud, tools.LOCAL);
    assert.equal((await assertSucceeds(clientStore.getDocs(clientStore.collection(store, "items")))).size, catalog.items.length);
    await assertSucceeds(clientStore.getDocs(clientStore.collection(store, "companies/default_company/invoices")));
    await assertSucceeds(clientStore.getDocs(clientStore.collection(store, "companies/default_company/cash_balances")));
    const sample = catalog.items[0];
    if (sample) {
      await assertSucceeds(clientStore.updateDoc(clientStore.doc(store, `items/${sample.id}`), {active: sample.data.active, updatedAt: clientStore.serverTimestamp()}));
    }
    await assertFails(clientStore.updateDoc(clientStore.doc(store, `users/${tools.ADMIN_UID}`), {role: "superadmin"}));
    await assertFails(clientStore.getDocs(clientStore.collection(store, "companies/unrelated_company/invoices")));
  });
  test("emulators: wrong password and unauthenticated catalog access are rejected", async () => {
    await assert.rejects(() => login(tools.EMAIL, "wrong-test-password"), (e) => ["auth/wrong-password", "auth/invalid-credential"].includes(e.code));
    await assertFails(clientStore.getDocs(clientStore.collection(rules.unauthenticatedContext().firestore(), "items")));
  });
  test("emulators: repeated bootstrap is idempotent and never resets altered inventory or business data", async () => {
    const second = await seed();
    assert.equal(second.createdDocuments, 0);
    const marker = db.doc("companies/default_company/customers/synthetic-history-guard");
    await marker.set({synthetic: true});
    await assert.rejects(seed, {code: "TEST_SETUP_BLOCKED"});
    assert.equal((await marker.get()).exists, true);
    await marker.delete();
    if (catalog.items.length) {
      const ref = db.doc(`items/${catalog.items[0].id}`);
      await ref.update({currentStock: 1});
      await assert.rejects(seed, {code: "TEST_SETUP_BLOCKED"});
      assert.equal((await ref.get()).data().currentStock, 1);
      await ref.update({currentStock: 0});
    }
  });
  test("emulators: another Firebase project cannot contaminate the local catalog namespace", async () => {
    const otherApp = initializeApp({projectId: "demo-fatoora-source-isolation"}, "source-isolation"), other = getFirestore(otherApp);
    try {
      const ref = other.doc("items/unrelated-private-source");
      await ref.set({name: "Synthetic unrelated catalog", currentStock: 999});
      const before = (await ref.get()).data();
      await seed();
      assert.equal((await db.doc("items/unrelated-private-source").get()).exists, false);
      assert.deepEqual((await ref.get()).data(), before);
    } finally { await deleteApp(otherApp); }
  });
}
