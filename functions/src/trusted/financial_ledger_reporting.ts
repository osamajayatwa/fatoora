import {createHash} from "node:crypto";
import {
  DocumentData,
  FieldPath,
  FieldValue,
  Firestore,
  Query,
  QueryDocumentSnapshot,
  Timestamp,
  Transaction,
  getFirestore,
} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  REGION,
  TRUSTED_CALLABLE_OPTIONS,
  businessPath,
  optionalString,
  record,
  requireCallableUid,
  requireTrustedUser,
  roundMoney,
  timestampFrom,
} from "./common";
import {
  FINANCIAL_LEDGER_SCHEMA_VERSION,
  buildLedgerSearchTokens,
  canonicalLedgerQueryKey,
  isLedgerQueryKeyHash,
  ledgerQueryKeyHash,
  ledgerSearchTokenHash,
  normalizeLedgerQueryKeysForSchemaV3,
  normalizeLedgerSearch,
} from "./financial_ledger";

const SEARCH_COLLECTION = "financial_ledger_search_entries";
const PROJECTION_STATE_COLLECTION = "financial_ledger_projection_states";
const SUMMARY_SCOPE_COLLECTION = "financial_ledger_summary_scopes";
const SEARCH_SCAN_BATCH_SIZE = 250;
const MAX_SEARCH_CANDIDATES_PER_PAGE = 1_000;
const MAX_SEARCH_SUMMARY_CANDIDATES = 10_000;
const MAX_PAGE_SIZE = 250;
const MAX_SALES_REP_ID_BYTES = 128;
export const LEDGER_SUMMARY_SHARD_COUNT = 16;

export const LEDGER_METRIC_FIELDS = [
  "metricSales",
  "metricCashSales",
  "metricCreditSales",
  "metricReceipts",
  "metricExpenses",
  "metricReturns",
  "metricSettlements",
  "metricReceivables",
  "metricCompanyCashNet",
  "metricRepCashIn",
  "metricRepCashOut",
] as const;

type LedgerMetricField = typeof LEDGER_METRIC_FIELDS[number];
type LedgerMetrics = Record<LedgerMetricField, number>;

export interface LedgerDerivedProjection {
  fingerprint: string;
  queryKeys: string[];
  searchTokens: string[];
  occurredAt: Timestamp;
  dayKey: string;
  summaryShard: string;
  salesRepId: string;
  metrics: LedgerMetrics;
  searchDocument: DocumentData;
}

interface ProjectionState {
  fingerprint: string;
  queryKeys: string[];
  dayKey: string;
  summaryShard: string;
  salesRepId: string;
  metrics: LedgerMetrics;
}

interface LedgerFilters {
  type: string;
  accountKey: string;
  customerId: string;
  paymentMethod: string;
  salesRepId: string;
  search: string;
  queryKey: string;
  indexedQueryKey: string;
}

interface SearchCursor {
  occurredAt: Timestamp;
  id: string;
}

interface SummaryAccumulator extends LedgerMetrics {
  entryCount: number;
}

export const projectFinancialLedgerEntry = onDocumentWritten(
  {
    document: "companies/{companyId}/financial_ledger_entries/{entryId}",
    region: REGION,
    retry: true,
  },
  async (event) => {
    await reconcileFinancialLedgerProjection(
      getFirestore(),
      String(event.params.companyId),
      String(event.params.entryId),
    );
  },
);

export const searchFinancialLedger = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    const uid = requireCallableUid(request, "searchFinancialLedger");
    const input = record(request.data);
    const companyId = requiredDocumentId(input.companyId, "companyId");
    const firestore = getFirestore();
    await requireLedgerAdmin(firestore, uid, companyId);
    const filters = parseFilters(input);
    if (filters.search.length < 2) {
      throw new HttpsError("invalid-argument", "search must contain at least two characters.");
    }
    const from = timestampFrom(input.from, "from");
    const to = timestampFrom(input.to, "to");
    validateDateRange(from, to);
    const pageSize = boundedInteger(input.pageSize, "pageSize", 1, MAX_PAGE_SIZE, 40);
    const cursor = parseCursor(input.cursor);
    return searchLedgerPage(firestore, companyId, filters, from, to, pageSize, cursor);
  },
);

export const getFinancialLedgerSummary = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    const uid = requireCallableUid(request, "getFinancialLedgerSummary");
    const input = record(request.data);
    const companyId = requiredDocumentId(input.companyId, "companyId");
    const firestore = getFirestore();
    await requireLedgerAdmin(firestore, uid, companyId);
    const filters = parseFilters(input);
    const from = timestampFrom(input.from, "from");
    const to = timestampFrom(input.to, "to");
    validateDateRange(from, to);
    return filters.search.length >= 2
      ? searchLedgerSummary(firestore, companyId, filters, from, to)
      : dailyLedgerSummary(firestore, companyId, filters, from, to);
  },
);

export async function reconcileFinancialLedgerProjection(
  firestore: Firestore,
  companyId: string,
  entryId: string,
): Promise<void> {
  const entryRef = firestore.doc(
    businessPath(companyId, "financial_ledger_entries", entryId),
  );
  const stateRef = firestore.doc(
    businessPath(companyId, PROJECTION_STATE_COLLECTION, entryId),
  );
  const searchRef = firestore.doc(
    businessPath(companyId, SEARCH_COLLECTION, entryId),
  );
  await firestore.runTransaction(async (transaction) => {
    const [entrySnapshot, stateSnapshot, searchSnapshot] = await transaction.getAll(
      entryRef,
      stateRef,
      searchRef,
    );
    const previous = stateSnapshot.exists
      ? parseProjectionState(stateSnapshot.data() ?? {})
      : null;
    const next = entrySnapshot.exists
      ? buildLedgerDerivedProjection(entryId, entrySnapshot.data() ?? {})
      : null;
    applyLedgerProjectionChanges(
      transaction,
      firestore,
      companyId,
      entryId,
      previous,
      next,
      searchProjectionIsCurrent(searchSnapshot.data(), next),
    );
  });
}

export function buildLedgerDerivedProjection(
  entryId: string,
  data: DocumentData,
): LedgerDerivedProjection {
  if (data.schemaVersion !== FINANCIAL_LEDGER_SCHEMA_VERSION) {
    throw new Error(
      `Financial ledger ${entryId} must use schemaVersion ${FINANCIAL_LEDGER_SCHEMA_VERSION}.`,
    );
  }
  if (!(data.occurredAt instanceof Timestamp)) {
    throw new Error(`Financial ledger ${entryId} occurredAt must be a Timestamp.`);
  }
  const queryKeys = normalizeLedgerQueryKeysForSchemaV3(data.queryKeys);
  if (queryKeys.some((key) => !isLedgerQueryKeyHash(key))) {
    throw new Error(`Financial ledger ${entryId} has an incompatible query key.`);
  }
  const salesRepId = scalarString(data.salesRepId, "salesRepId", MAX_SALES_REP_ID_BYTES);
  const metrics = ledgerMetrics(data);
  const searchTokens = buildLedgerSearchTokens([
    scalarString(data.referenceNumber, "referenceNumber"),
    scalarString(data.customerName, "customerName"),
    scalarString(data.description, "description"),
    scalarString(data.notes, "notes"),
  ]);
  const dayKey = businessDayKey(data.occurredAt);
  const summaryShard = ledgerSummaryShard(entryId);
  const fingerprint = projectionFingerprint({
    queryKeys,
    searchTokens,
    occurredAtSeconds: data.occurredAt.seconds,
    occurredAtNanoseconds: data.occurredAt.nanoseconds,
    summaryShard,
    salesRepId,
    metrics,
  });
  return {
    fingerprint,
    queryKeys,
    searchTokens,
    occurredAt: data.occurredAt,
    dayKey,
    summaryShard,
    salesRepId,
    metrics,
    searchDocument: {
      schemaVersion: FINANCIAL_LEDGER_SCHEMA_VERSION,
      ledgerEntryId: entryId,
      occurredAt: data.occurredAt,
      salesRepId,
      queryKeys,
      searchTokens,
      fingerprint,
    },
  };
}

export function applyLedgerProjectionChanges(
  transaction: Transaction,
  firestore: Firestore,
  companyId: string,
  entryId: string,
  previous: ProjectionState | null,
  next: LedgerDerivedProjection | null,
  searchIsCurrent = false,
): void {
  const searchRef = firestore.doc(businessPath(companyId, SEARCH_COLLECTION, entryId));
  if (previous?.fingerprint === next?.fingerprint) {
    if (!next || searchIsCurrent) return;
    transaction.set(searchRef, next.searchDocument);
    return;
  }
  const deltas = new Map<string, SummaryAccumulator>();
  if (previous) addProjectionDeltas(deltas, companyId, previous, -1);
  if (next) addProjectionDeltas(deltas, companyId, next, 1);
  for (const [path, delta] of deltas) {
    if (isZeroSummary(delta)) continue;
    const update: DocumentData = {
      schemaVersion: FINANCIAL_LEDGER_SCHEMA_VERSION,
      updatedAt: FieldValue.serverTimestamp(),
      entryCount: FieldValue.increment(delta.entryCount),
    };
    for (const field of LEDGER_METRIC_FIELDS) {
      update[field] = FieldValue.increment(roundMoney(delta[field]));
    }
    transaction.set(firestore.doc(path), update, {merge: true});
  }

  const stateRef = firestore.doc(
    businessPath(companyId, PROJECTION_STATE_COLLECTION, entryId),
  );
  if (!next) {
    transaction.delete(searchRef);
    transaction.delete(stateRef);
    return;
  }
  transaction.set(searchRef, next.searchDocument);
  transaction.set(stateRef, {
    schemaVersion: FINANCIAL_LEDGER_SCHEMA_VERSION,
    ledgerEntryId: entryId,
    fingerprint: next.fingerprint,
    queryKeys: next.queryKeys,
    dayKey: next.dayKey,
    summaryShard: next.summaryShard,
    salesRepId: next.salesRepId,
    metrics: next.metrics,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

function searchProjectionIsCurrent(
  data: DocumentData | undefined,
  expected: LedgerDerivedProjection | null,
): boolean {
  if (!expected) return data === undefined;
  if (!data || data.schemaVersion !== FINANCIAL_LEDGER_SCHEMA_VERSION) return false;
  if (data.ledgerEntryId !== expected.searchDocument.ledgerEntryId) return false;
  if (data.salesRepId !== expected.salesRepId || data.fingerprint !== expected.fingerprint) {
    return false;
  }
  if (!(data.occurredAt instanceof Timestamp) || !data.occurredAt.isEqual(expected.occurredAt)) {
    return false;
  }
  return stringArraysEqual(data.queryKeys, expected.queryKeys) &&
    stringArraysEqual(data.searchTokens, expected.searchTokens);
}

function stringArraysEqual(value: unknown, expected: string[]): boolean {
  return Array.isArray(value) && value.length === expected.length &&
    value.every((item, index) => item === expected[index]);
}

function addProjectionDeltas(
  deltas: Map<string, SummaryAccumulator>,
  companyId: string,
  projection: Pick<
    ProjectionState,
    "queryKeys" | "dayKey" | "summaryShard" | "salesRepId" | "metrics"
  >,
  direction: -1 | 1,
): void {
  const scopes = ["all"];
  if (projection.salesRepId) scopes.push(representativeScopeId(projection.salesRepId));
  for (const scope of scopes) {
    for (const queryKey of projection.queryKeys) {
      const path = summaryDayPath(
        companyId,
        scope,
        queryKey,
        projection.dayKey,
        projection.summaryShard,
      );
      const delta = deltas.get(path) ?? emptySummary();
      delta.entryCount += direction;
      for (const field of LEDGER_METRIC_FIELDS) {
        delta[field] = roundMoney(delta[field] + projection.metrics[field] * direction);
      }
      deltas.set(path, delta);
    }
  }
}

async function searchLedgerPage(
  firestore: Firestore,
  companyId: string,
  filters: LedgerFilters,
  from: Timestamp,
  to: Timestamp,
  pageSize: number,
  initialCursor: SearchCursor | null,
): Promise<DocumentData> {
  const matches: QueryDocumentSnapshot[] = [];
  let cursor = initialCursor;
  let scanned = 0;
  let exhausted = false;
  while (matches.length <= pageSize && scanned < MAX_SEARCH_CANDIDATES_PER_PAGE) {
    const remaining = MAX_SEARCH_CANDIDATES_PER_PAGE - scanned;
    const limit = Math.min(SEARCH_SCAN_BATCH_SIZE, remaining);
    let query = searchQuery(firestore, companyId, filters, from, to);
    if (cursor) query = query.startAfter(cursor.occurredAt, cursor.id);
    const snapshot = await query.limit(limit).get();
    if (snapshot.empty) {
      exhausted = true;
      break;
    }
    for (const document of snapshot.docs) {
      scanned += 1;
      cursor = searchCursorFromDocument(document);
      if (projectionHasQueryKey(document.data(), filters.indexedQueryKey)) {
        matches.push(document);
        if (matches.length > pageSize) break;
      }
    }
    if (matches.length > pageSize) break;
    if (snapshot.size < limit) {
      exhausted = true;
      break;
    }
  }

  const visible = matches.slice(0, pageSize);
  const pageCursor = matches.length > pageSize
    ? searchCursorFromDocument(visible.at(-1)!)
    : cursor;
  const entries = await fetchLedgerEntries(
    firestore,
    companyId,
    visible.map((document) => document.id),
  );
  return {
    entries,
    cursor: pageCursor ? cursorForClient(pageCursor) : null,
    hasMore: matches.length > pageSize || !exhausted,
    candidatesScanned: scanned,
  };
}

async function dailyLedgerSummary(
  firestore: Firestore,
  companyId: string,
  filters: LedgerFilters,
  from: Timestamp,
  to: Timestamp,
): Promise<SummaryAccumulator> {
  const scope = filters.salesRepId
    ? representativeScopeId(filters.salesRepId)
    : "all";
  const days = firestore.collection(
    `companies/${companyId}/${SUMMARY_SCOPE_COLLECTION}/${scope}/` +
    `query_keys/${filters.indexedQueryKey}/days`,
  );
  const snapshot = await days
    .where(FieldPath.documentId(), ">=", `${businessDayKey(from)}_s00`)
    .where(
      FieldPath.documentId(),
      "<=",
      `${businessDayKey(to)}_s${String(LEDGER_SUMMARY_SHARD_COUNT - 1).padStart(2, "0")}`,
    )
    .get();
  const result = emptySummary();
  for (const document of snapshot.docs) addDataToSummary(result, document.data());
  return result;
}

async function searchLedgerSummary(
  firestore: Firestore,
  companyId: string,
  filters: LedgerFilters,
  from: Timestamp,
  to: Timestamp,
): Promise<SummaryAccumulator> {
  const result = emptySummary();
  let cursor: SearchCursor | null = null;
  let scanned = 0;
  while (true) {
    let query = searchQuery(firestore, companyId, filters, from, to);
    if (cursor) query = query.startAfter(cursor.occurredAt, cursor.id);
    const snapshot = await query.limit(SEARCH_SCAN_BATCH_SIZE).get();
    if (snapshot.empty) break;
    scanned += snapshot.size;
    if (scanned > MAX_SEARCH_SUMMARY_CANDIDATES) {
      throw new HttpsError(
        "resource-exhausted",
        "Search summary is too broad; refine the search or date range.",
      );
    }
    const matchingIds = snapshot.docs
      .filter((document) => projectionHasQueryKey(document.data(), filters.indexedQueryKey))
      .map((document) => document.id);
    const entries = await fetchLedgerEntryData(firestore, companyId, matchingIds);
    for (const entry of entries) addLedgerEntryToSummary(result, entry);
    cursor = searchCursorFromDocument(snapshot.docs.at(-1)!);
    if (snapshot.size < SEARCH_SCAN_BATCH_SIZE) break;
  }
  return result;
}

function searchQuery(
  firestore: Firestore,
  companyId: string,
  filters: LedgerFilters,
  from: Timestamp,
  to: Timestamp,
): Query {
  const searchToken = ledgerSearchTokenHash(filters.search.slice(0, 20));
  let query: Query = firestore
    .collection(`companies/${companyId}/${SEARCH_COLLECTION}`)
    .where("searchTokens", "array-contains", searchToken)
    .where("occurredAt", ">=", from)
    .where("occurredAt", "<=", to);
  if (filters.salesRepId) query = query.where("salesRepId", "==", filters.salesRepId);
  return query
    .orderBy("occurredAt", "desc")
    .orderBy(FieldPath.documentId(), "desc");
}

async function fetchLedgerEntries(
  firestore: Firestore,
  companyId: string,
  ids: string[],
): Promise<DocumentData[]> {
  const entries = await fetchLedgerEntryData(firestore, companyId, ids);
  return entries.map(ledgerEntryForClient);
}

async function fetchLedgerEntryData(
  firestore: Firestore,
  companyId: string,
  ids: string[],
): Promise<DocumentData[]> {
  if (ids.length === 0) return [];
  const refs = ids.map((id) => firestore.doc(
    businessPath(companyId, "financial_ledger_entries", id),
  ));
  const snapshots = await firestore.getAll(...refs);
  return snapshots
    .filter((snapshot) => snapshot.exists)
    .map((snapshot) => ({id: snapshot.id, ...(snapshot.data() ?? {})}));
}

function ledgerEntryForClient(data: DocumentData): DocumentData {
  const occurredAt = data.occurredAt;
  if (!(occurredAt instanceof Timestamp)) {
    throw new HttpsError("data-loss", "A financial ledger entry has an invalid date.");
  }
  return {
    id: optionalString(data.id),
    occurredAt: occurredAt.toMillis(),
    type: optionalString(data.type),
    component: optionalString(data.component),
    description: optionalString(data.description),
    amount: finiteMetric(data.amount, "amount"),
    quantity: finiteMetric(data.quantity, "quantity"),
    unitPrice: finiteMetric(data.unitPrice, "unitPrice"),
    debitAccountType: optionalString(data.debitAccountType),
    debitAccountKey: optionalString(data.debitAccountKey),
    debitAccountName: optionalString(data.debitAccountName),
    creditAccountType: optionalString(data.creditAccountType),
    creditAccountKey: optionalString(data.creditAccountKey),
    creditAccountName: optionalString(data.creditAccountName),
    customerId: optionalString(data.customerId),
    customerName: optionalString(data.customerName),
    salesRepId: optionalString(data.salesRepId),
    salesRepName: optionalString(data.salesRepName),
    paymentMethod: optionalString(data.paymentMethod),
    referenceType: optionalString(data.referenceType),
    referenceId: optionalString(data.referenceId),
    referenceNumber: optionalString(data.referenceNumber),
    sourceCollection: optionalString(data.sourceCollection),
    sourceId: optionalString(data.sourceId),
    notes: optionalString(data.notes),
  };
}

function parseFilters(input: Record<string, unknown>): LedgerFilters {
  const type = scalarString(input.type, "type");
  const accountKey = scalarString(input.accountKey, "accountKey");
  const customerId = scalarString(input.customerId, "customerId");
  const paymentMethod = scalarString(input.paymentMethod, "paymentMethod");
  const salesRepId = scalarString(input.salesRepId, "salesRepId", MAX_SALES_REP_ID_BYTES);
  const search = normalizeLedgerSearch(scalarString(input.search, "search")).slice(0, 20);
  const queryKey = canonicalLedgerQueryKey({
    type,
    accountKey,
    customerId,
    paymentMethod,
  });
  return {
    type,
    accountKey,
    customerId,
    paymentMethod,
    salesRepId,
    search,
    queryKey,
    indexedQueryKey: ledgerQueryKeyHash(queryKey),
  };
}

function parseCursor(value: unknown): SearchCursor | null {
  if (value === null || value === undefined) return null;
  const cursor = record(value);
  const id = requiredDocumentId(cursor.id, "cursor.id");
  return {id, occurredAt: timestampFrom(cursor.occurredAt, "cursor.occurredAt")};
}

function cursorForClient(cursor: SearchCursor): DocumentData {
  return {id: cursor.id, occurredAt: cursor.occurredAt.toMillis()};
}

function searchCursorFromDocument(document: QueryDocumentSnapshot): SearchCursor {
  const occurredAt = document.get("occurredAt");
  if (!(occurredAt instanceof Timestamp)) {
    throw new HttpsError("data-loss", "A search projection has an invalid date.");
  }
  return {occurredAt, id: document.id};
}

function projectionHasQueryKey(data: DocumentData, queryKey: string): boolean {
  return Array.isArray(data.queryKeys) && data.queryKeys.includes(queryKey);
}

function parseProjectionState(data: DocumentData): ProjectionState {
  if (data.schemaVersion !== FINANCIAL_LEDGER_SCHEMA_VERSION) {
    throw new Error("Financial ledger projection state has an incompatible schemaVersion.");
  }
  const fingerprint = scalarString(data.fingerprint, "fingerprint");
  const dayKey = scalarString(data.dayKey, "dayKey");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dayKey)) {
    throw new Error("Financial ledger projection state has an invalid dayKey.");
  }
  const summaryShard = scalarString(data.summaryShard, "summaryShard");
  if (!/^s(?:0[0-9]|1[0-5])$/.test(summaryShard)) {
    throw new Error("Financial ledger projection state has an invalid summaryShard.");
  }
  return {
    fingerprint,
    dayKey,
    summaryShard,
    queryKeys: normalizeLedgerQueryKeysForSchemaV3(data.queryKeys),
    salesRepId: scalarString(data.salesRepId, "salesRepId", MAX_SALES_REP_ID_BYTES),
    metrics: ledgerMetrics(record(data.metrics)),
  };
}

function ledgerMetrics(data: DocumentData): LedgerMetrics {
  const metrics = {} as LedgerMetrics;
  for (const field of LEDGER_METRIC_FIELDS) metrics[field] = finiteMetric(data[field], field);
  return metrics;
}

function finiteMetric(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`Financial ledger ${field} must be numeric.`);
  }
  return roundMoney(value);
}

function addDataToSummary(result: SummaryAccumulator, data: DocumentData): void {
  const count = data.entryCount;
  if (typeof count !== "number" || !Number.isFinite(count)) {
    throw new HttpsError("data-loss", "A financial ledger summary count is invalid.");
  }
  result.entryCount += Math.trunc(count);
  for (const field of LEDGER_METRIC_FIELDS) {
    result[field] = roundMoney(result[field] + finiteMetric(data[field], field));
  }
}

function addLedgerEntryToSummary(
  result: SummaryAccumulator,
  data: DocumentData,
): void {
  result.entryCount += 1;
  for (const field of LEDGER_METRIC_FIELDS) {
    result[field] = roundMoney(result[field] + finiteMetric(data[field], field));
  }
}

function emptySummary(): SummaryAccumulator {
  return {
    entryCount: 0,
    metricSales: 0,
    metricCashSales: 0,
    metricCreditSales: 0,
    metricReceipts: 0,
    metricExpenses: 0,
    metricReturns: 0,
    metricSettlements: 0,
    metricReceivables: 0,
    metricCompanyCashNet: 0,
    metricRepCashIn: 0,
    metricRepCashOut: 0,
  };
}

function isZeroSummary(value: SummaryAccumulator): boolean {
  return value.entryCount === 0 && LEDGER_METRIC_FIELDS.every((field) => value[field] === 0);
}

function summaryDayPath(
  companyId: string,
  scope: string,
  queryKey: string,
  dayKey: string,
  summaryShard: string,
): string {
  return `companies/${companyId}/${SUMMARY_SCOPE_COLLECTION}/${scope}/` +
    `query_keys/${queryKey}/days/${dayKey}_${summaryShard}`;
}

export function ledgerSummaryShard(entryId: string): string {
  const digest = createHash("sha256").update(entryId, "utf8").digest();
  const shard = digest.readUInt32BE(0) % LEDGER_SUMMARY_SHARD_COUNT;
  return `s${String(shard).padStart(2, "0")}`;
}

function representativeScopeId(salesRepId: string): string {
  const digest = createHash("sha256").update(salesRepId, "utf8").digest("base64url");
  return `rep_${digest}`;
}

function businessDayKey(value: Timestamp): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Amman",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(value.toDate());
  const part = (type: Intl.DateTimeFormatPartTypes): string =>
    parts.find((item) => item.type === type)?.value ?? "";
  const result = `${part("year")}-${part("month")}-${part("day")}`;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(result)) {
    throw new Error("Unable to derive the financial ledger business day.");
  }
  return result;
}

function projectionFingerprint(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(value), "utf8").digest("base64url");
}

async function requireLedgerAdmin(
  firestore: Firestore,
  uid: string,
  companyId: string,
): Promise<void> {
  const user = await firestore.runTransaction((transaction) =>
    requireTrustedUser(transaction, firestore, uid, companyId));
  if (user.role !== "admin") {
    throw new HttpsError("permission-denied", "Financial ledger access requires an admin.");
  }
}

function validateDateRange(from: Timestamp, to: Timestamp): void {
  if (from.toMillis() > to.toMillis()) {
    throw new HttpsError("invalid-argument", "from must not be after to.");
  }
}

function scalarString(value: unknown, field: string, maxBytes = 1_500): string {
  if (value === undefined || value === null) return "";
  if (typeof value !== "string") throw new Error(`Financial ledger ${field} must be a string.`);
  const result = value.trim();
  if (Buffer.byteLength(result, "utf8") > maxBytes) {
    throw new Error(`Financial ledger ${field} exceeds ${maxBytes} bytes.`);
  }
  return result;
}

function requiredDocumentId(value: unknown, field: string): string {
  const result = scalarString(value, field);
  if (!result || result.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return result;
}

function boundedInteger(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
  fallback: number,
): number {
  if (value === undefined || value === null) return fallback;
  if (typeof value !== "number" || !Number.isInteger(value) ||
      value < minimum || value > maximum) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be an integer from ${minimum} to ${maximum}.`,
    );
  }
  return value;
}
