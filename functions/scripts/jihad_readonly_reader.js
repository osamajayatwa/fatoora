"use strict";
// The only remote methods exposed here are read RPCs. No Admin write handles.
const PROJECT = "fatoora-6b192";
const LIMITS = Object.freeze({invoices: 200, profiles: 20, rep_inventory_movements: 1000,
  rep_inventory_balances: 500, inventory_transfers: 200, sales_returns: 400, audit_events: 1000,
  receipts: 400, customer_transactions: 1200, cash_movements: 1000, financial_ledger_entries: 1200,
  items: 500, customers: 200, stock_movements: 1000, totalDocuments: 5000, requests: 500, durationMs: 600000});
const FIELDS = Object.freeze({
  users: ["uid", "name", "role", "companyId", "active", "approvalStatus"],
  invoices: ["companyId", "salesRepId", "createdByUid", "createdByRole", "invoiceStatus", "financialPosted", "inventoryPosted",
    "stockSourceType", "stockSourceSalesRepId", "inventoryMovementIds", "items", "customerId", "grandTotal", "subtotal", "totalDiscount", "totalTax",
    "paidAmount", "initialPaidAmount", "initialCashAccount", "remainingAmount", "paymentType", "receiptIds", "cancelledReceiptIds", "returnInvoiceIds",
    "customerTransactionIds", "cashMovementIds", "returnedTotal", "returnedReceivableAmount", "cashRefundAmount", "customerCreditAmount",
    "returnedQuantitiesByItem", "createdAt", "financialPostedAt", "inventoryPostedAt"],
  items: ["companyId", "trackStock", "active", "deleted", "currentStock", "warehouseId"],
  rep_inventory_balances: ["companyId", "salesRepId", "itemId", "quantity", "lastMovementId", "hasStock"],
  rep_inventory_movements: ["companyId", "salesRepId", "itemId", "direction", "quantity", "quantityBefore", "quantityAfter", "referenceType", "referenceId", "reason", "sourceLineId", "sourceLineIndex", "createdAt"],
  stock_movements: ["companyId", "itemId", "direction", "quantity", "quantityBefore", "quantityAfter", "referenceType", "referenceId", "movementType", "sourceLineId", "sourceLineIndex", "warehouseId", "createdAt"],
  inventory_transfers: ["companyId", "salesRepId", "status", "type", "lines", "confirmedAt", "effectsVersion"],
  sales_returns: ["companyId", "salesRepId", "originalInvoiceId", "customerId", "status", "financialPosted", "inventoryPosted", "items", "grandTotal",
    "receivableReduction", "customerCreditAmount", "cashRefundAmount", "refundType", "stockMovementIds", "cashMovementIds", "customerTransactionIds", "createdAt"],
  receipts: ["companyId", "customerId", "createdByUid", "createdByRole", "status", "amount", "paymentMethod", "invoiceAllocations", "cashMovementIds",
    "receiptLedgerOwnershipVersion", "financialLedgerOwnerGroups", "customerTransactionIds", "cancellationVersion", "cancellationCashMovementIds", "cancellationCustomerTransactionIds", "createdAt"],
  customers: ["companyId", "currentBalance", "totalSales", "totalPaid", "lastOpeningBalanceTransactionId"],
  customer_transactions: ["companyId", "customerId", "sourceCollection", "sourceId", "referenceId", "invoiceId", "receiptId", "transactionType", "type",
    "debitAmount", "creditAmount", "balanceBefore", "balanceAfter", "createdAt"],
  cash_movements: ["companyId", "customerId", "sourceCollection", "sourceId", "referenceId", "cashAccount", "salesRepId", "direction", "amount", "balanceBefore", "balanceAfter", "reversesMovementId"],
  financial_ledger_entries: ["companyId", "sourceCollection", "sourceId", "component", "customerId", "amount", "debitAccountKey", "creditAccountKey", "isReversal", "reversesEntryId", "salesRepId", "paymentMethod"],
  audit_events: ["companyId", "entityType", "entityId", "action", "occurredAt", "recordedAt", "changedFields"],
});
const LINE_FIELDS = new Set(["lineId", "lineType", "itemId", "quantity", "unitPrice", "discount", "taxPercent", "subtotal", "taxAmount", "total", "stockTrackedAtPosting",
  "originalIndex", "originalInvoiceItemId", "returnedQuantity", "discountAmount", "companyMovementId", "repMovementId", "warehouseQuantityBefore", "warehouseQuantityAfter", "repQuantityBefore", "repQuantityAfter"]);
class Blocked extends Error {constructor(code) {super(code); this.code = code;}}
function documentId(value) {
  if (typeof value !== "string" || !value || value !== value.trim() || value.includes("/") || value === "." || value === ".." || Buffer.byteLength(value) > 1500) throw new Blocked("INVALID_DOCUMENT_ID");
  return value;
}
const eq = (field, value) => ({fieldFilter: {field: {fieldPath: field}, op: "EQUAL", value: typeof value === "boolean" ? {booleanValue: value} : {stringValue: value}}});
const oneOf = (field, values) => ({fieldFilter: {field: {fieldPath: field}, op: "IN", value: {arrayValue: {values: values.map((stringValue) => ({stringValue}))}}}});
const combine = (op, filters) => filters.length === 1 ? filters[0] : {compositeFilter: {op, filters}};
function decode(value) {
  if ("stringValue" in value) return value.stringValue;
  if ("timestampValue" in value) return value.timestampValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("nullValue" in value) return null;
  if ("integerValue" in value) {const n = Number(value.integerValue); if (!Number.isSafeInteger(n)) throw new Blocked("UNSUPPORTED_NUMBER_RANGE"); return n;}
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("arrayValue" in value) return (value.arrayValue.values || []).map(decode);
  if ("mapValue" in value) return Object.fromEntries(Object.entries(value.mapValue.fields || {}).map(([key, entry]) => [key, decode(entry)]));
  throw new Blocked("UNSUPPORTED_FIRESTORE_VALUE");
}
function minimize(collection, row) {
  if (Array.isArray(row.items)) row.items = row.items.map((line) => Object.fromEntries(Object.entries(line).filter(([key]) => LINE_FIELDS.has(key))));
  if (Array.isArray(row.lines)) row.lines = row.lines.map((line) => Object.fromEntries(Object.entries(line).filter(([key]) => LINE_FIELDS.has(key))));
  if (Array.isArray(row.financialLedgerOwnerGroups)) row.financialLedgerOwnerGroups = row.financialLedgerOwnerGroups.map((group) => ({salesRepId: group.salesRepId, amount: group.amount, ownershipSource: group.ownershipSource}));
  if (collection === "audit_events" && row.changes) row.changes = row.changes.filter((change) => change.field === "trackStock" && typeof change.before === "boolean" && typeof change.after === "boolean")
    .map(({field, before, after}) => ({field, before, after}));
  return row;
}
class ReadonlyReader {
  constructor({project, request, emulator = false}) {
    if (project !== PROJECT && !(emulator && /^demo-[a-z0-9-]+$/.test(project))) throw new Blocked("UNAPPROVED_PROJECT");
    this.project = project; this.request = request; this.emulator = emulator;
    this.root = `projects/${project}/databases/(default)/documents`;
    this.readTime = null; this.started = Date.now(); this.counts = {requests: 0, documents: 0, missing: 0, aggregations: 0, byCollection: {}};
    this.seenInvoices = new Set();
  }
  async rpc(method, body) {
    if (!["runQuery", "runAggregationQuery", "batchGet"].includes(method)) throw new Blocked("NON_READ_RPC_REJECTED");
    if (++this.counts.requests > LIMITS.requests || Date.now() - this.started > LIMITS.durationMs) throw new Blocked("REQUEST_OR_TIME_BUDGET");
    const pinned = this.readTime;
    const rows = await this.request(method, {...body, ...(pinned ? {readTime: pinned} : {})});
    if (!Array.isArray(rows) || !rows.length) throw new Blocked("READ_TIME_EVIDENCE_MISSING");
    for (const row of rows) {
      if (typeof row.readTime !== "string") throw new Blocked("READ_TIME_EVIDENCE_MISSING");
      if (!this.readTime) this.readTime = row.readTime;
      if (row.readTime !== this.readTime) throw new Blocked("INCONSISTENT_READ_TIME");
    }
    return rows;
  }
  fields(collection, itemAudit = false) {
    if (!FIELDS[collection]) throw new Blocked("UNAPPROVED_COLLECTION");
    return [...FIELDS[collection], "id", ...(itemAudit ? ["changes"] : [])];
  }
  accept(document, collection) {
    const prefix = collection === "users" || collection === "items" ? `${this.root}/${collection}/` : `${this.root}/companies/${this.company}/${collection}/`;
    if (!document.name.startsWith(prefix)) throw new Blocked("OUT_OF_SCOPE_DOCUMENT_PATH");
    const id = documentId(document.name.slice(prefix.length));
    if (++this.counts.documents + this.counts.missing > LIMITS.totalDocuments) throw new Blocked("DOCUMENT_BUDGET");
    this.counts.byCollection[collection] = (this.counts.byCollection[collection] || 0) + 1;
    if (collection === "invoices") {this.seenInvoices.add(id); if (this.seenInvoices.size > LIMITS.invoices) throw new Blocked("INVOICE_LIMIT");}
    const fields = Object.fromEntries(Object.entries(document.fields || {}).map(([field, value]) => [field, decode(value)]));
    if (fields.id !== undefined && fields.id !== id) throw new Blocked("PERSISTED_DOCUMENT_ID_MISMATCH");
    return minimize(collection, {...fields, id});
  }
  baseQuery(collection, where) {
    this.fields(collection);
    return {from: [{collectionId: collection}], ...(where ? {where} : {})};
  }
  parent(collection) {return ["users", "items"].includes(collection) ? "" : `companies/${documentId(this.company)}`;}
  async count(collection, where) {
    const parent = this.parent(collection);
    const rows = await this.rpc("runAggregationQuery", {parent, structuredAggregationQuery: {structuredQuery: this.baseQuery(collection, where), aggregations: [{alias: "n", count: {}}]}});
    this.counts.aggregations++;
    const n = rows[0].result?.aggregateFields?.n?.integerValue;
    if (typeof n !== "string" || !/^\d+$/.test(n) || BigInt(n) > BigInt(Number.MAX_SAFE_INTEGER)) throw new Blocked("INVALID_QUERY_COUNT");
    return Number(n);
  }
  async scan(collection, where, cap, {itemAudit = false, orderField} = {}) {
    if (orderField && (collection !== "users" || orderField !== "name")) throw new Blocked("UNAPPROVED_QUERY_ORDER");
    const count = await this.count(collection, where);
    if (count > cap || count > LIMITS.totalDocuments - this.counts.documents - this.counts.missing) throw new Blocked(`${collection.toUpperCase()}_LIMIT`);
    const found = []; let cursor;
    while (found.length < count) {
      const query = {...this.baseQuery(collection, where), select: {fields: this.fields(collection, itemAudit).map((fieldPath) => ({fieldPath}))},
        orderBy: [...(orderField ? [{field: {fieldPath: orderField}, direction: "ASCENDING"}] : []), {field: {fieldPath: "__name__"}, direction: "ASCENDING"}], limit: Math.min(25, count - found.length),
        ...(cursor ? {startAt: {values: cursor, before: false}} : {})};
      const rows = await this.rpc("runQuery", {parent: this.parent(collection), structuredQuery: query});
      const documents = rows.filter((row) => row.document).map((row) => row.document);
      if (!documents.length || documents.length > query.limit) throw new Blocked("QUERY_COVERAGE_MISMATCH");
      found.push(...documents.map((doc) => this.accept(doc, collection)));
      const last = documents.at(-1);
      const next = [...(orderField ? [last.fields[orderField]] : []), {referenceValue: last.name}];
      if (JSON.stringify(next) === JSON.stringify(cursor)) throw new Blocked("NON_ADVANCING_CURSOR"); cursor = next;
    }
    if (new Set(found.map((row) => row.id)).size !== count) throw new Blocked("QUERY_COVERAGE_MISMATCH");
    return found;
  }
  async getMany(collection, ids) {
    const unique = [...new Set(ids.map(documentId))];
    if (collection === "invoices" && new Set([...this.seenInvoices, ...unique]).size > LIMITS.invoices) throw new Blocked("INVOICE_LIMIT");
    if (unique.length > LIMITS.totalDocuments - this.counts.documents - this.counts.missing) throw new Blocked("DOCUMENT_BUDGET");
    const found = [];
    for (let start = 0; start < unique.length; start += 25) {
      const ids_ = unique.slice(start, start + 25);
      const prefix = `${this.root}/${this.parent(collection) ? this.parent(collection) + "/" : ""}${collection}/`;
      const rows = await this.rpc("batchGet", {documents: ids_.map((id) => prefix + id), mask: {fieldPaths: this.fields(collection)}});
      if (rows.length !== ids_.length) throw new Blocked("BATCH_COVERAGE_MISMATCH");
      const seen = new Set();
      for (const row of rows) {
        const name = row.found?.name || row.missing;
        if (!ids_.some((id) => prefix + id === name) || seen.has(name)) throw new Blocked("BATCH_COVERAGE_MISMATCH");
        seen.add(name);
        if (row.found) found.push(this.accept(row.found, collection));
        else if (row.missing) this.counts.missing++;
        else throw new Blocked("BATCH_COVERAGE_MISMATCH");
      }
    }
    return found;
  }
}
async function productionReader() {
  if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST || process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    ["DEBUG", "NODE_DEBUG", "GRPC_TRACE", "GOOGLE_SDK_NODE_LOGGING"].some((key) => process.env[key])) throw new Blocked("UNSAFE_AUTH_OR_DEBUG_CONTEXT");
  const {GoogleAuth} = require("google-auth-library");
  let timer, client;
  try {
    client = await Promise.race([
      new GoogleAuth({projectId: PROJECT, scopes: ["https://www.googleapis.com/auth/datastore"]}).getClient(),
      new Promise((_, reject) => {timer = setTimeout(() => reject(new Blocked("AUTH_DISCOVERY_TIMEOUT")), 8000);}),
    ]);
  } finally {clearTimeout(timer);}
  if (client.constructor.name !== "UserRefreshClient") throw new Blocked("EXISTING_USER_ADC_REQUIRED");
  const reader = new ReadonlyReader({project: PROJECT, request: async (method, body) => {
    const parent = body.parent; const input = {...body}; delete input.parent;
    const url = `https://firestore.googleapis.com/v1/${reader.root}${parent ? "/" + parent : ""}:${method}`;
    return (await client.request({url, method: "POST", data: input, timeout: 20000, retry: false})).data;
  }});
  return reader;
}
function emulatorReader(project, host, onRequest = () => {}) {
  if (!/^127\.0\.0\.1:\d+$/.test(host) || !/^demo-[a-z0-9-]+$/.test(project)) throw new Blocked("INVALID_EMULATOR_CONTEXT");
  const reader = new ReadonlyReader({project, emulator: true, request: async (method, body) => {
    const parent = body.parent; const input = {...body}; delete input.parent;
    onRequest(method, input);
    // Standard emulator-only Admin authentication; never available in the CLI.
    const response = await fetch(`http://${host}/v1/${reader.root}${parent ? "/" + parent : ""}:${method}`, {
      method: "POST", headers: {"Content-Type": "application/json", Authorization: "Bearer owner"}, body: JSON.stringify(input), signal: AbortSignal.timeout(20000)});
    if (!response.ok) throw new Blocked(`EMULATOR_HTTP_${response.status}`);
    return response.json();
  }});
  return reader;
}
module.exports = {PROJECT, LIMITS, FIELDS, Blocked, ReadonlyReader, eq, oneOf, combine, documentId, productionReader, emulatorReader};
