"use strict";
// Phase 2B-14: preparation only. No deployment, callable invocation, login,
// production probe, business write, full export or history reconstruction.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const root = path.resolve(__dirname, ".."), PROJECT = "fatoora-original-staging", COMPANY = "default_company";
const BASE = `/v1/projects/${PROJECT}/databases/(default)`, DOCUMENTS = `${BASE}/documents`;
const LIMITS = Object.freeze({requests: 40, returnedDocuments: 512, responseBytes: 8 * 1024 * 1024, collectionSample: 64, countLimit: 16001, milliseconds: 120000});
const hash = value => crypto.createHash("sha256").update(value).digest("hex");
function need(ok, message) {if (!ok) throw new Error(message);}
function assertReadRequest(url, method = "GET", data) {
  const u = new URL(url);need(u.protocol === "https:" && !u.username && !u.password && !u.hash, "Pinned HTTPS staging reads only");
  const database = u.hostname === "firestore.googleapis.com" && u.pathname === BASE;
  const documents = u.hostname === "firestore.googleapis.com" && u.pathname === `${DOCUMENTS}/companies/${COMPANY}`;
  const functions = u.hostname === "cloudfunctions.googleapis.com" && u.pathname === `/v2/projects/${PROJECT}/locations/us-central1/functions`;
  const policy = u.hostname === "cloudresourcemanager.googleapis.com" && u.pathname === `/v3/projects/${PROJECT}:getIamPolicy`;
  const query = u.hostname === "firestore.googleapis.com" && (u.pathname === `${DOCUMENTS}/companies/${COMPANY}:runQuery` || u.pathname === `${DOCUMENTS}:runQuery`);
  const aggregate = u.hostname === "firestore.googleapis.com" && u.pathname === `${DOCUMENTS}/companies/${COMPANY}:runAggregationQuery`;
  need(method === "GET" && (database || documents || functions) || method === "POST" && policy && JSON.stringify(data) === "{}" ||
    method === "POST" && (query || aggregate), "Request is not a permitted staging read");
  if (query) {
    const q = data?.structuredQuery, id = q?.from?.[0]?.collectionId;
    const companyQuery = u.pathname === `${DOCUMENTS}/companies/${COMPANY}:runQuery`;
    need(q && q.from.length === 1 && !q.from[0].allDescendants && Number.isInteger(q.limit) && q.limit > 0 && q.limit <= LIMITS.collectionSample && q.select?.fields?.length,
      "Bounded projected collection query required");
    need(Object.keys(q).every(k => ["from", "select", "limit", ...(companyQuery ? [] : ["where"])].includes(k)) &&
      q.select.fields.every(f => fields[id]?.includes(f.fieldPath)), "Unreviewed query/projection refused");
    need(companyQuery ? ["cash_movements", "invoices", "receipts", "sales_returns", "expenses", "settlements", "cash_balances", "books"].includes(id) :
      id === "users" && q.where?.fieldFilter?.field?.fieldPath === "companyId" && q.where.fieldFilter.op === "EQUAL" && q.where.fieldFilter.value?.stringValue === COMPANY,
    "Unscoped company/profile read refused");
  }
  if (aggregate) {
    const a = data?.structuredAggregationQuery, q = a?.structuredQuery;
    need(q?.from?.length === 1 && !q.from[0].allDescendants && ["cash_movements", "invoices", "receipts", "sales_returns", "expenses", "settlements"].includes(q.from[0].collectionId) &&
      q.limit === LIMITS.countLimit && a.aggregations?.length === 1 && a.aggregations[0].alias === "boundedCount" && JSON.stringify(a.aggregations[0].count) === "{}",
    "Unbounded/unsupported aggregate refused");
    need(Object.keys(q).every(k => ["from", "limit"].includes(k)), "Unreviewed aggregate query refused");
  }
}
function decode(value) {
  if (!value) return undefined;
  if ("stringValue" in value) return value.stringValue;
  if ("integerValue" in value) {const n = Number(value.integerValue);return Number.isSafeInteger(n) ? n : String(value.integerValue);}
  if ("doubleValue" in value) return value.doubleValue; // observed only; never monetary reconstruction
  if ("booleanValue" in value) return value.booleanValue;
  if ("nullValue" in value) return null;
  if ("timestampValue" in value) return value.timestampValue;
  if (value.arrayValue) return (value.arrayValue.values ?? []).map(decode);
  if (value.mapValue) return Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(([k,v]) => [k,decode(v)]));
  return undefined;
}
const fields = {
  cash_movements: ["cashAccount", "salesRepId", "holderUid", "holderType", "treasuryAccountId", "movementType", "type", "immutable", "currency", "moneyScale", "sourceCollection", "sourceId", "sourceNumber", "referenceId", "referenceNumber", "counterpartMovementId", "createdByUid", "sellerId", "collectorUid", "postedByUid"],
  invoices: ["financialPosted", "invoiceStatus", "paymentType", "initialPaidAmount", "grandTotal", "initialCashAccount", "cashMovementIds", "receiptIds", "invoiceNumber", "currency", "moneyScale"],
  receipts: ["amount", "paymentMethod", "status", "cashMovementIds", "invoiceAllocations", "invoiceAllocationDetails", "receiptNumber", "currency", "moneyScale"],
  sales_returns: ["status", "refundType", "cashRefundAmount", "cashMovementIds", "originalInvoiceId", "returnNumber", "currency", "moneyScale"],
  expenses: ["status", "fundingSource", "cashMovementId", "currency", "moneyScale"],
  settlements: ["status", "salesRepId", "repMovementId", "companyMovementId", "sourceCashAccount", "sourceCashAccountId", "destinationCashAccountId", "accounting", "settlementNumber", "currency", "moneyScale"],
  cash_balances: ["cashAccount", "salesRepId", "lastMovementId", "currency", "moneyScale"],
  books: ["id", "companyId", "approvalStatus", "journalPostingEnabled", "currency", "moneyScale", "cashEvidenceCurrencyBindingId"],
  users: ["uid", "companyId", "role", "active", "approvalStatus"],
};
async function inspect() {
  const started = Date.now(), {connect} = require("./staging-release-support.cjs"), {reader} = await connect(false);
  const report = {phase: "2B-14", project: PROJECT, company: COMPANY, at: new Date().toISOString(), remoteWrites: 0,
    scope: "bounded_read_only_prerequisite_inventory_not_financial_certification", limits: LIMITS, requests: 0, returnedDocuments: 0, responseBytes: 0, observations: {}};
  async function request(url, method = "GET", data) {
    assertReadRequest(url, method, data);
    need(++report.requests <= LIMITS.requests && Date.now() - started < LIMITS.milliseconds, "Inspection request/time bound reached");
    try {
      const value = (await reader.request({url, method, data, retry: false, timeout: 20000, maxRedirects: 0,
        agent: new (require("node:https").Agent)({family: 4})})).data;
      report.responseBytes += Buffer.byteLength(JSON.stringify(value));need(report.responseBytes <= LIMITS.responseBytes, "Inspection response bound reached");return value;
    } catch (e) {if (e.response?.status === 404) return null;throw e;}
  }
  async function query(collection, profile = false) {
    const parent = profile ? DOCUMENTS : `${DOCUMENTS}/companies/${COMPANY}`;
    const data = {structuredQuery: {from: [{collectionId: collection}], select: {fields: fields[collection].map(fieldPath => ({fieldPath}))}, limit: LIMITS.collectionSample,
      ...(profile ? {where: {fieldFilter: {field: {fieldPath: "companyId"}, op: "EQUAL", value: {stringValue: COMPANY}}}} : {})}};
    const response = await request(`https://firestore.googleapis.com${parent}:runQuery`, "POST", data);
    const rows = (response ?? []).filter(r => r.document).map(r => ({idHash: hash(r.document.name), createTime: r.document.createTime,
      updateTime: r.document.updateTime, data: Object.fromEntries(Object.entries(r.document.fields ?? {}).map(([k,v]) => [k,decode(v)]))}));
    report.returnedDocuments += rows.length;need(report.returnedDocuments <= LIMITS.returnedDocuments, "Inspection document bound reached");
    return {rows, readTimes: [...new Set((response ?? []).map(r => r.readTime).filter(Boolean))]};
  }
  const db = await request(`https://firestore.googleapis.com${BASE}`);
  report.database = db && {name: db.name, locationId: db.locationId, type: db.type, databaseEdition: db.databaseEdition};
  const functions = await request(`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions?pageSize=100`);
  need(!functions?.nextPageToken, "Function inventory exceeds inspection page bound");
  report.functions = (functions?.functions ?? []).map(f => ({name: f.name.split("/").at(-1), state: f.state, runtime: f.buildConfig?.runtime,
    revision: f.serviceConfig?.revision, serviceAccount: f.serviceConfig?.serviceAccountEmail}));
  report.breakdownEndpointExists = report.functions.some(f => f.name === "getSettlementBreakdown");
  const policy = await request(`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}:getIamPolicy`, "POST", {});
  const principals = new Set(report.functions.map(f => `serviceAccount:${f.serviceAccount}`));
  report.currentRuntimeProjectRoles = (policy?.bindings ?? []).filter(b => b.members?.some(m => principals.has(m))).map(b => ({role: b.role, conditional: Boolean(b.condition)}));
  const company = await request(`https://firestore.googleapis.com${DOCUMENTS}/companies/${COMPANY}?mask.fieldPaths=id&mask.fieldPaths=active&mask.fieldPaths=activeBookId`);
  report.companyEvidence = company ? Object.fromEntries(Object.entries(company.fields ?? {}).map(([k,v]) => [k,decode(v)])) : null;
  const books = await query("books"), users = await query("users", true), balances = await query("cash_balances");
  report.books = {sampled: books.rows.length, ...{readTimes: books.readTimes}, records: books.rows.map(b => ({idHash: b.idHash, ...b.data, sdkImmutable: b.createTime === b.updateTime}))};
  report.profiles = {sampled: users.rows.length, readTimes: users.readTimes, approvedActiveAdministrators: users.rows.filter(r => r.data.role === "admin" && r.data.active === true && r.data.approvalStatus === "approved").length,
    representatives: users.rows.filter(r => r.data.role === "sales_rep").length};
  report.balances = {sampled: balances.rows.length, readTimes: balances.readTimes, currencyMissing: balances.rows.filter(r => r.data.currency === undefined || r.data.moneyScale !== 3).length,
    headReferenceMissing: balances.rows.filter(r => !r.data.lastMovementId).length};
  for (const collection of ["cash_movements", "invoices", "receipts", "sales_returns", "expenses", "settlements"]) {
    const aggregate = await request(`https://firestore.googleapis.com${DOCUMENTS}/companies/${COMPANY}:runAggregationQuery`, "POST", {
      structuredAggregationQuery: {structuredQuery: {from: [{collectionId: collection}], limit: LIMITS.countLimit}, aggregations: [{alias: "boundedCount", count: {}}]}});
    const count = Number(aggregate?.find(r => r.result?.aggregateFields)?.result.aggregateFields.boundedCount.integerValue);
    need(Number.isSafeInteger(count) && count >= 0 && count <= LIMITS.countLimit, "Invalid bounded aggregate response");
    const sample = await query(collection), rows = sample.rows, status = key => Object.fromEntries([...new Set(rows.map(r => String(r.data[key] ?? "missing")))].map(v => [v, rows.filter(r => String(r.data[key] ?? "missing") === v).length]));
    report.observations[collection] = {boundedCount: count, countCapped: count === LIMITS.countLimit, sampled: rows.length, sampleCoversObservedCount: rows.length === count,
      aggregateReadTimes: aggregate.map(r => r.readTime).filter(Boolean), sampleReadTimes: sample.readTimes,
      statuses: status(collection === "invoices" ? "invoiceStatus" : "status"), currencyMissingInSample: rows.filter(r => r.data.currency === undefined || r.data.moneyScale !== 3).length,
      documentNumberMissingInSample: rows.filter(r => !r.data.sourceNumber && !r.data.referenceNumber && !r.data.invoiceNumber && !r.data.receiptNumber && !r.data.returnNumber && !r.data.settlementNumber).length};
    const o = report.observations[collection];
    if (collection === "cash_movements") Object.assign(o, {movementKinds: status("movementType"), sourceReferencesMissing: rows.filter(r => !r.data.sourceCollection || !r.data.sourceId).length,
      explicitOpeningCandidates: rows.filter(r => [r.data.type,r.data.movementType].includes("opening_balance")).map(r => ({idHash: r.idHash, immutableFlag: r.data.immutable === true,
        sdkImmutable: r.createTime === r.updateTime, currency: r.data.currency ?? null, scale: r.data.moneyScale ?? null})), holderMetadataMissing: rows.filter(r => !r.data.holderUid || !r.data.holderType || !r.data.treasuryAccountId).length});
    if (collection === "invoices") Object.assign(o, {paymentKinds: status("paymentType"), posted: rows.filter(r => r.data.financialPosted === true).length});
    if (collection === "receipts") Object.assign(o, {cashReceipts: rows.filter(r => r.data.paymentMethod === "cash").length, allocationEvidencePresent: rows.filter(r => r.data.invoiceAllocations || r.data.invoiceAllocationDetails).length});
    if (collection === "sales_returns") Object.assign(o, {refundKinds: status("refundType"), positiveCashRefunds: rows.filter(r => Number(r.data.cashRefundAmount) > 0).length});
    if (collection === "expenses") o.fundingKinds = status("fundingSource");
    if (collection === "settlements") Object.assign(o, {posted: rows.filter(r => r.data.status === "posted").length, pairedMovementReferences: rows.filter(r => r.data.repMovementId && r.data.companyMovementId).length,
      atomicAccountingReferences: rows.filter(r => r.data.accounting).length});
  }
  report.elapsedMillis = Date.now() - started;
  const output = path.join(root, "output/phase2b14");fs.mkdirSync(output, {recursive: true});fs.writeFileSync(path.join(output, "staging-inspection.json"), JSON.stringify(report, null, 2)+"\n");
  console.log(JSON.stringify({project: PROJECT, remoteWrites: 0, requests: report.requests, returnedDocuments: report.returnedDocuments,
    endpointExists: report.breakdownEndpointExists, books: report.books.sampled, settlements: report.observations.settlements.boundedCount}));
  return report;
}
if (require.main === module) {
  need(process.argv.length === 3 && process.argv[2] === "inspect", "Explicit read-only inspect action required");
  inspect().catch(e => {console.error(JSON.stringify({status: "HOLD_INSPECTION_INCOMPLETE", message: String(e.message), httpStatus: e.response?.status}));process.exitCode = 1;});
}
module.exports = {assertReadRequest, LIMITS};
