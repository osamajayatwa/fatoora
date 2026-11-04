"use strict";

// One existing app/schema. Production capability is a projected catalog READ
// only; every bootstrap write requires both loopback emulators and a demo ID.
const {createHash} = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {documentSearchFields} = require("../shared/search_keywords");
const PRODUCTION = "fatoora-6b192", LOCAL = "demo-fatoora-test", COMPANY = "default_company";
const EMAIL = "admin@fatoora.com", ADMIN_UID = "local-test-admin";
const FIELDS = ["id", "companyId", "code", "name", "description", "unit", "price", "taxRate", "active", "deleted",
  "trackStock", "barcode", "category", "sku", "brand", "model", "specifications", "specs", "attributes"];
const HISTORY = ["customers", "invoices", "quotations", "receipts", "sales_returns", "expenses", "cash_movements",
  "cash_balances", "settlements", "stock_movements", "inventory_transfers", "rep_inventory_balances",
  "rep_inventory_movements", "customer_transactions", "financial_ledger_entries"];
function check(condition, message) { if (!condition) throw Object.assign(new Error(message), {code: "TEST_SETUP_BLOCKED"}); }
function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  return value;
}
function digest(value) { return createHash("sha256").update(JSON.stringify(stable(value)) ?? "undefined").digest("hex"); }
function safeId(value) {
  check(typeof value === "string" && value.length > 0 && value.length <= 256 && !value.includes("/") && value !== "." && value !== "..", "Invalid item ID.");
  return value;
}
function safeSpecs(value, depth = 0) {
  check(depth <= 6, "Specification nesting exceeds the supported limit.");
  if (value === null || typeof value === "boolean" || typeof value === "string") return value;
  if (typeof value === "number") { check(Number.isFinite(value), "Invalid specification number."); return value; }
  if (Array.isArray(value)) { check(value.length <= 100, "Specification array too large."); return value.map((v) => safeSpecs(v, depth + 1)); }
  check(value && typeof value === "object" && Object.keys(value).length <= 100, "Invalid specification object.");
  return Object.fromEntries(Object.entries(value).map(([key, entry]) => {
    check(!/password|secret|token|supplier|cost|margin|balance|customer|invoice|cash|stock/i.test(key), "Sensitive or inventory field in specifications; review required.");
    return [key, safeSpecs(entry, depth + 1)];
  }));
}
function sanitizeCatalog(documents) {
  check(Array.isArray(documents) && documents.length <= 5000, "Catalog exceeds 5,000 items.");
  const seen = new Set(), items = [];
  for (const row of documents) {
    const id = safeId(row.id), data = row.data;
    check(data && typeof data === "object", "Missing catalog definition.");
    // Missing ownership is the deployed legacy root catalog, not another tenant.
    if (data.companyId !== undefined && data.companyId !== COMPANY) {
      check(typeof data.companyId === "string" && data.companyId.length > 0, "Ambiguous source item ownership.");
      continue;
    }
    check(!seen.has(id), "Duplicate catalog ID."); seen.add(id);
    check(data.id === id, "Source item ID does not match its document.");
    for (const field of ["code", "name", "description", "unit"]) {
      check(typeof data[field] === "string" && data[field].trim().length > 0, `Invalid catalog ${field}.`);
    }
    for (const field of ["price", "taxRate"]) check(typeof data[field] === "number" && Number.isFinite(data[field]) && data[field] >= 0, `Invalid catalog ${field}.`);
    check(data.taxRate <= 100, "Invalid catalog taxRate.");
    for (const field of ["active", "deleted"]) check(typeof data[field] === "boolean", `Invalid catalog ${field}.`);
    if (data.trackStock !== undefined) check(typeof data.trackStock === "boolean", "Invalid stock-tracking flag.");
    const definition = Object.fromEntries(FIELDS.filter((field) => field !== "companyId" && data[field] !== undefined)
      .map((field) => [field, safeSpecs(data[field])]));
    items.push({id, data: definition});
  }
  return {schemaVersion: 1, sourceProjectId: PRODUCTION, sourceCompanyId: COMPANY, items: items.sort((a, b) => a.id.localeCompare(b.id))};
}
function validateBundle(bundle) {
  check(bundle && bundle.schemaVersion === 1 && bundle.sourceProjectId === PRODUCTION && bundle.sourceCompanyId === COMPANY,
    "Expected a sanitized default_company production catalog bundle.");
  check(Array.isArray(bundle.items), "Missing catalog items.");
  check(bundle.items.every((row) => row.data && (row.data.companyId === undefined || row.data.companyId === COMPANY)), "Conflicting source company in catalog file.");
  // Re-sanitize untrusted files; extra inventory, creator and cost fields never survive.
  return sanitizeCatalog(bundle.items.map((row) => ({id: row.id, data: {...row.data, companyId: COMPANY}})));
}
function localContext(projectId, firestoreHost, authHost) {
  check(/^demo-[a-z0-9-]+$/.test(projectId) && projectId !== PRODUCTION, "Bootstrap writes require a demo project.");
  for (const host of [firestoreHost, authHost]) check(/^127\.0\.0\.1:\d+$/.test(host || ""), "Both loopback emulators are required; no cloud fallback.");
}
function targetItem(row) {
  const data = {...row.data, id: row.id, companyId: COMPANY, currentStock: 0, openingStock: 0, minStock: 0,
    costPrice: 0, inventoryValue: 0, warehouseId: "default_warehouse", trackStock: row.data.trackStock !== false,
    createdBy: ADMIN_UID, localTestCatalogHash: digest(row.data)};
  data.stockStatus = data.trackStock ? "out" : "untracked";
  data.nameLower = data.name.trim().toLowerCase();
  Object.assign(data, documentSearchFields("items", data));
  return data;
}
async function seedLocalEnvironment({app, firestore, auth, bundle, password}) {
  localContext(app.options.projectId, process.env.FIRESTORE_EMULATOR_HOST, process.env.FIREBASE_AUTH_EMULATOR_HOST);
  check(firestore.projectId === app.options.projectId && auth.app.options.projectId === app.options.projectId, "SDK project mismatch.");
  check(typeof password === "string" && password.length >= 12, "Choose a test-only password of at least 12 characters.");
  const catalog = validateBundle(bundle);
  const company = firestore.doc(`companies/${COMPANY}`), profile = firestore.doc(`users/${ADMIN_UID}`);
  for (const name of HISTORY) check((await company.collection(name).limit(1).get()).empty, "Existing test business data: bootstrap will not overwrite or reset it.");
  const existingItems = await firestore.collection("items").get();
  const expected = new Map(catalog.items.map((row) => [row.id, targetItem(row)]));
  for (const doc of existingItems.docs) {
    check(expected.has(doc.id), "Existing test catalog contains an unrelated item.");
    const data = doc.data(), item = expected.get(doc.id);
    check(Object.entries(item).every(([key, value]) => digest(data[key]) === digest(value)), "Existing item changed; bootstrap refuses to reset it.");
  }
  const profileSnapshot = await profile.get(), companySnapshot = await company.get();
  const wantedProfile = {uid: ADMIN_UID, name: "Test Administrator", email: EMAIL, phone: "", photoUrl: "",
    role: "admin", active: true, approvalStatus: "approved", companyId: COMPANY};
  if (profileSnapshot.exists) check(Object.entries(wantedProfile).every(([key, value]) => profileSnapshot.data()[key] === value), "Existing local admin profile conflicts.");
  if (companySnapshot.exists) check(companySnapshot.data().localTestBootstrap === 1, "Existing company was not created by this local bootstrap.");
  let account;
  try { account = await auth.getUserByEmail(EMAIL); } catch (error) { if (error.code !== "auth/user-not-found") throw error; }
  if (account) check(account.uid === ADMIN_UID && !account.disabled, "Existing test Auth account conflicts.");
  else account = await auth.createUser({uid: ADMIN_UID, email: EMAIL, password, displayName: "Test Administrator", emailVerified: true});
  const {FieldValue} = require("firebase-admin/firestore");
  const stamp = () => FieldValue.serverTimestamp();
  // Create-only batches, never overwrite existing data on replay. Not a history reset.
  const additions = [];
  if (!companySnapshot.exists) additions.push([company, {id: COMPANY, name: "Fatoora Test", localTestBootstrap: 1, createdAt: stamp()}]);
  if (!profileSnapshot.exists) additions.push([profile, {...wantedProfile, createdAt: stamp(), updatedAt: stamp()}]);
  const settings = company.collection("settings").doc("app");
  if (!(await settings.get()).exists) additions.push([settings, {companyId: COMPANY,
    companySettings: {name: "Fatoora Test", country: "", email: EMAIL, website: "", phone: "", address: "", logoEnabled: false},
    jofotaraStatusSettings: {enabled: false, status: "not_configured"}}]);
  const present = new Set(existingItems.docs.map((doc) => doc.id));
  for (const [id, data] of expected) if (!present.has(id)) additions.push([firestore.doc(`items/${id}`), {...data, createdAt: stamp(), updatedAt: stamp(), inventoryUpdatedAt: stamp()}]);
  for (let i = 0; i < additions.length; i += 400) {
    const batch = firestore.batch();
    for (const [ref, data] of additions.slice(i, i + 400)) batch.create(ref, data);
    await batch.commit();
  }
  return {projectId: app.options.projectId, companyId: COMPANY, email: EMAIL, role: "admin", catalogItems: catalog.items.length,
    createdDocuments: additions.length, existingItems: present.size, inventoryQuantities: 0, copiedHistoryDocuments: 0};
}
function decode(value) {
  if ("stringValue" in value) return value.stringValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("nullValue" in value) return null;
  if ("doubleValue" in value) { check(Number.isFinite(value.doubleValue), "Invalid catalog number."); return value.doubleValue; }
  if ("integerValue" in value) { const n = Number(value.integerValue); check(Number.isSafeInteger(n), "Unsafe catalog number."); return n; }
  if ("arrayValue" in value) return (value.arrayValue.values || []).map(decode);
  if ("mapValue" in value) return Object.fromEntries(Object.entries(value.mapValue.fields || {}).map(([k, v]) => [k, decode(v)]));
  throw Object.assign(new Error("Unsupported catalog value; review required."), {code: "TEST_SETUP_BLOCKED"});
}
async function exportCatalog(request) {
  const root = `projects/${PRODUCTION}/databases/(default)/documents`, rows = [];
  let cursor, readTime;
  do {
    const body = {structuredQuery: {from: [{collectionId: "items"}], select: {fields: FIELDS.map((fieldPath) => ({fieldPath}))},
      orderBy: [{field: {fieldPath: "__name__"}, direction: "ASCENDING"}], limit: 100,
      ...(cursor ? {startAt: {values: [{referenceValue: cursor}], before: false}} : {})}, ...(readTime ? {readTime} : {})};
    const page = await request(`https://firestore.googleapis.com/v1/${root}:runQuery`, body);
    const documents = page.filter((row) => row.document).map((row) => row.document);
    const time = page.find((row) => row.readTime)?.readTime;
    check(time && (!readTime || time === readTime), "Catalog export requires a consistent server read time.");
    readTime = time;
    for (const doc of documents) {
      check(doc.name.startsWith(`${root}/items/`) && doc.name.slice(`${root}/items/`.length).indexOf("/") === -1, "Unexpected catalog document target.");
      rows.push({id: doc.name.slice(`${root}/items/`.length), data: Object.fromEntries(Object.entries(doc.fields || {}).map(([k, v]) => [k, decode(v)]))});
    }
    check(rows.length <= 5000, "Source catalog exceeds 5,000 items.");
    const next = documents.at(-1)?.name;
    check(!next || next !== cursor, "Catalog cursor did not advance.");
    cursor = documents.length === 100 ? next : undefined;
  } while (cursor);
  return sanitizeCatalog(rows);
}
async function main(args) {
  if (args.includes("--help")) {
    process.stdout.write("Export (read-only): --export-catalog=<new JSON path>\nSeed (emulators only): --seed --catalog=<JSON path>\nSeed password: FATOORA_TEST_ADMIN_PASSWORD (never logged). No remote writes/reset/deploy mode.\n"); return;
  }
  const exportArg = args.find((a) => a.startsWith("--export-catalog=")), catalogArg = args.find((a) => a.startsWith("--catalog="));
  check(args.every((a) => a === "--seed" || a.startsWith("--export-catalog=") || a.startsWith("--catalog=")), "Unsupported option.");
  if (exportArg) {
    check(args.length === 1 && !process.env.FIRESTORE_EMULATOR_HOST && !process.env.FIREBASE_AUTH_EMULATOR_HOST, "Production read export must not mix with emulator context.");
    const {GoogleAuth} = require("google-auth-library");
    const client = await new GoogleAuth({projectId: PRODUCTION, scopes: ["https://www.googleapis.com/auth/datastore"]}).getClient();
    check(client.constructor.name === "UserRefreshClient", "Existing authorized user ADC required; no token extraction or credential copying.");
    const bundle = await exportCatalog(async (url, data) => (await client.request({url, method: "POST", data, timeout: 15000, retry: false})).data);
    const file = path.resolve(exportArg.slice("--export-catalog=".length));
    check(file.endsWith(".json"), "JSON export path required.");
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, JSON.stringify(bundle, null, 2) + "\n", {flag: "wx", mode: 0o600});
    process.stdout.write(JSON.stringify({sourceProjectId: PRODUCTION, sourceCompanyId: COMPANY, exportedItems: bundle.items.length,
      catalogDigest: digest(bundle), productionWrites: 0, file}) + "\n");
    return;
  }
  check(args.length === 2 && args.includes("--seed") && catalogArg, "Specify --seed --catalog=<file>, or --export-catalog=<new file>.");
  localContext(LOCAL, process.env.FIRESTORE_EMULATOR_HOST, process.env.FIREBASE_AUTH_EMULATOR_HOST);
  const bundle = JSON.parse(fs.readFileSync(path.resolve(catalogArg.slice("--catalog=".length)), "utf8"));
  const {initializeApp, deleteApp} = require("firebase-admin/app");
  const {getFirestore} = require("firebase-admin/firestore"), {getAuth} = require("firebase-admin/auth");
  const app = initializeApp({projectId: LOCAL});
  try { process.stdout.write(JSON.stringify(await seedLocalEnvironment({app, firestore: getFirestore(app), auth: getAuth(app),
    bundle, password: process.env.FATOORA_TEST_ADMIN_PASSWORD})) + "\n"); } finally { await deleteApp(app); }
}
if (require.main === module) main(process.argv.slice(2)).catch((error) => {
  // Never dump SDK/Gaxios objects, request headers, tokens or input passwords.
  process.stderr.write(JSON.stringify({status: "BLOCKED", code: error.code || "ERROR", httpStatus: error.response?.status || null,
    ...(error.code === "TEST_SETUP_BLOCKED" ? {reason: error.message} : {}), productionWrites: 0}) + "\n"); process.exitCode = 1;
});
module.exports = {sanitizeCatalog, validateBundle, targetItem, localContext, seedLocalEnvironment, exportCatalog, PRODUCTION, LOCAL, COMPANY, EMAIL, ADMIN_UID};
