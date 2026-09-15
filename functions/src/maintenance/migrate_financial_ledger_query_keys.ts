import {getApps, initializeApp} from "firebase-admin/app";
import {
  DocumentData,
  DocumentReference,
  FieldPath,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {
  FINANCIAL_LEDGER_SCHEMA_VERSION,
  LEDGER_QUERY_KEY_HASH_BYTES,
  MAX_LEDGER_QUERY_KEYS,
  MAX_LEDGER_QUERY_KEY_INDEXED_VALUE_BYTES,
  MAX_LEDGER_SEARCH_TOKENS,
  buildLedgerQueryKeys,
} from "../trusted/financial_ledger";
import {
  LEDGER_SUMMARY_SHARD_COUNT,
  buildLedgerDerivedProjection,
  reconcileFinancialLedgerProjection,
} from "../trusted/financial_ledger_reporting";

const LEDGER_COLLECTION = "financial_ledger_entries";
const SEARCH_COLLECTION = "financial_ledger_search_entries";
const STATE_COLLECTION = "financial_ledger_projection_states";
const MAX_INDEX_ENTRIES_PER_DOCUMENT = 40_000;
const MAX_INDEX_BYTES_PER_DOCUMENT = 8 * 1024 * 1024;
const MAX_INDEXED_VALUE_BYTES = 1_500;
const MAX_LEGACY_QUERY_KEYS = 40_000;

interface Options {
  projectId: string;
  companyId: string;
  apply: boolean;
  confirmProject: string;
  confirmCompany: string;
  pageSize: number;
  maxWrites: number;
}

interface IndexField {
  fieldPath: string;
  order?: "ASCENDING" | "DESCENDING";
  arrayConfig?: "CONTAINS";
}

interface IndexDefinition {
  collectionGroup: string;
  queryScope: string;
  fields: IndexField[];
}

interface CompositeEstimate {
  entries: number;
  bytes: number;
  largestEntryBytes: number;
}

interface MigrationPlan {
  id: string;
  path: string;
  ref: DocumentReference<DocumentData>;
  updateTime: Timestamp;
  queryKeys: string[];
  searchTokenCount: number;
  oldKeyCount: number;
  mainNeedsUpdate: boolean;
  projectionNeedsUpdate: boolean;
  estimatedWriteUpperBound: number;
  current: CompositeEstimate;
  proposedMain: CompositeEstimate;
  proposedSearch: CompositeEstimate;
}

interface InvalidDocument {
  path: string;
  reason: string;
}

const OLD_LEDGER_INDEXES: IndexDefinition[] = [
  index([contains("queryKeys"), ascending("occurredAt")]),
  index([contains("queryKeys"), descending("occurredAt")]),
  index([contains("queryKeys"), ascending("salesRepId"), ascending("occurredAt")]),
  index([contains("queryKeys"), ascending("salesRepId"), descending("occurredAt")]),
  index([
    contains("queryKeys"), ascending("occurredAt"), ascending("metricCashSales"),
    ascending("metricCreditSales"), ascending("metricReceipts"), ascending("metricSales"),
  ]),
  index([
    contains("queryKeys"), ascending("salesRepId"), ascending("occurredAt"),
    ascending("metricCashSales"), ascending("metricCreditSales"),
    ascending("metricReceipts"), ascending("metricSales"),
  ]),
  index([
    contains("queryKeys"), ascending("occurredAt"), ascending("metricCompanyCashNet"),
    ascending("metricExpenses"), ascending("metricReceivables"),
    ascending("metricReturns"), ascending("metricSettlements"),
  ]),
  index([
    contains("queryKeys"), ascending("salesRepId"), ascending("occurredAt"),
    ascending("metricCompanyCashNet"), ascending("metricExpenses"),
    ascending("metricReceivables"), ascending("metricReturns"),
    ascending("metricSettlements"),
  ]),
  index([
    contains("queryKeys"), ascending("occurredAt"), ascending("metricRepCashIn"),
    ascending("metricRepCashOut"),
  ]),
  index([
    contains("queryKeys"), ascending("salesRepId"), ascending("occurredAt"),
    ascending("metricRepCashIn"), ascending("metricRepCashOut"),
  ]),
];

async function main(): Promise<void> {
  const options = parseOptions(process.argv.slice(2));
  validateApplyOptions(options);
  if (getApps().length === 0) initializeApp({projectId: options.projectId});
  const firestore = getFirestore();
  const manifest = readAndValidateManifest();
  const scan = await scanLedger(firestore, options, manifest);
  if (options.apply && scan.invalid.length > 0) {
    throw new Error("Apply blocked because one or more ledger documents failed validation.");
  }
  const estimatedWrites = scan.plans.reduce(
    (sum, plan) => sum + plan.estimatedWriteUpperBound,
    0,
  );
  if (options.apply && estimatedWrites > options.maxWrites) {
    throw new Error(
      `Apply blocked: estimated ${estimatedWrites} writes exceeds --max-writes=${options.maxWrites}.`,
    );
  }
  if (options.apply) await applyPlans(firestore, options.companyId, scan.plans);

  const current = totalEstimate(scan.plans.map((plan) => plan.current));
  const proposedMain = totalEstimate(scan.plans.map((plan) => plan.proposedMain));
  const proposedSearch = totalEstimate(scan.plans.map((plan) => plan.proposedSearch));
  const proposed = addEstimates(proposedMain, proposedSearch);
  const report = {
    mode: options.apply ? "apply" : "dry-run",
    projectId: options.projectId,
    companyId: options.companyId,
    sourceCollectionPath: `companies/${options.companyId}/${LEDGER_COLLECTION}`,
    sourceFinancialCollectionsRead: false,
    sourceFinancialDocumentsWritten: false,
    mainLedgerUpdateMask: ["queryKeys", "schemaVersion"],
    targetSchemaVersion: FINANCIAL_LEDGER_SCHEMA_VERSION,
    guards: {
      maxMainQueryKeys: MAX_LEDGER_QUERY_KEYS,
      mainHashAlgorithm: "SHA-256",
      mainHashEncoding: "base64url-no-padding",
      mainHashPrefix: "v3:",
      mainHashBytesPerKey: LEDGER_QUERY_KEY_HASH_BYTES,
      maxMainIndexedValueBytes: MAX_LEDGER_QUERY_KEY_INDEXED_VALUE_BYTES,
      maxSearchTokens: MAX_LEDGER_SEARCH_TOKENS,
      searchHashPrefix: "v3s:",
      applyWriteCeiling: options.maxWrites,
      updateTimePreconditions: true,
    },
    documents: {
      scanned: scan.scanned,
      valid: scan.scanned - scan.invalid.length,
      invalid: scan.invalid.length,
      plans: scan.plans.length,
      mainUpdates: scan.plans.filter((plan) => plan.mainNeedsUpdate).length,
      projectionReconciliations: scan.plans.filter((plan) => plan.projectionNeedsUpdate).length,
      estimatedWriteUpperBound: estimatedWrites,
      applyExecuted: options.apply,
    },
    queryKeys: {
      before: keyStats(scan.plans.map((plan) => plan.oldKeyCount)),
      after: keyStats(scan.plans.map((plan) => plan.queryKeys.length)),
      maximumAfter: MAX_LEDGER_QUERY_KEYS,
      searchMultiplicationRemoved: true,
    },
    derivedProjection: {
      searchCollection: SEARCH_COLLECTION,
      stateCollection: STATE_COLLECTION,
      maxSearchTokensPerDocument: MAX_LEDGER_SEARCH_TOKENS,
      maxDailySummaryTargetsPerLedgerEntry: 48,
      dailySummaryShardsPerScopeAndQueryKey: LEDGER_SUMMARY_SHARD_COUNT,
      idempotency: "per-entry fingerprint plus atomic projection reconciliation",
    },
    indexConfiguration: {
      oldMainCompositeIndexes: OLD_LEDGER_INDEXES.length,
      proposedMainCompositeIndexes: manifest.main.length,
      proposedSearchCompositeIndexes: manifest.search.length,
      metricCompositeIndexes: 0,
      queryKeysSingleFieldExempt: manifest.mainQueryKeysExempt,
      searchTokensSingleFieldExempt: manifest.searchTokensExempt,
      searchQueryKeysSingleFieldExempt: manifest.searchQueryKeysExempt,
    },
    compositeIndexEstimate: {
      current: {
        ...current,
        largestDocumentEntries: current.entries,
        largestDocumentBytes: current.bytes,
      },
      proposed: {
        ...proposed,
        mainEntries: proposedMain.entries,
        mainBytes: proposedMain.bytes,
        searchEntries: proposedSearch.entries,
        searchBytes: proposedSearch.bytes,
        largestDocumentEntries: Math.max(proposedMain.entries, proposedSearch.entries),
        largestDocumentBytes: Math.max(proposedMain.bytes, proposedSearch.bytes),
      },
      reduction: {
        entries: current.entries - proposed.entries,
        bytes: current.bytes - proposed.bytes,
        entryPercent: percentageReduction(current.entries, proposed.entries),
        bytePercent: percentageReduction(current.bytes, proposed.bytes),
      },
      firestoreLimitsPerDocument: {
        maxEntries: MAX_INDEX_ENTRIES_PER_DOCUMENT,
        maxTotalBytes: MAX_INDEX_BYTES_PER_DOCUMENT,
        maxIndexedFieldValueBytes: MAX_INDEXED_VALUE_BYTES,
      },
    },
    plannedDocuments: scan.plans.slice(0, 100).map((plan) => ({
      id: plan.id,
      path: plan.path,
      schemaVersion: FINANCIAL_LEDGER_SCHEMA_VERSION,
      oldKeyCount: plan.oldKeyCount,
      newKeyCount: plan.queryKeys.length,
      searchTokenCount: plan.searchTokenCount,
      mainNeedsUpdate: plan.mainNeedsUpdate,
      projectionNeedsUpdate: plan.projectionNeedsUpdate,
      estimatedWriteUpperBound: plan.estimatedWriteUpperBound,
      mainFieldsChanged: plan.mainNeedsUpdate ? ["queryKeys", "schemaVersion"] : [],
    })),
    truncatedPlannedDocuments: Math.max(scan.plans.length - 100, 0),
    invalidDocuments: scan.invalid.slice(0, 100),
    truncatedInvalidDocuments: Math.max(scan.invalid.length - 100, 0),
  };
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

async function scanLedger(
  firestore: Firestore,
  options: Options,
  manifest: ReturnType<typeof readAndValidateManifest>,
): Promise<{
  scanned: number;
  plans: MigrationPlan[];
  invalid: InvalidDocument[];
}> {
  const collection = firestore
    .collection("companies")
    .doc(options.companyId)
    .collection(LEDGER_COLLECTION);
  const plans: MigrationPlan[] = [];
  const invalid: InvalidDocument[] = [];
  let scanned = 0;
  let cursor: QueryDocumentSnapshot<DocumentData> | undefined;
  do {
    let query = collection.orderBy(FieldPath.documentId()).limit(options.pageSize);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    const stateSnapshots = page.empty ? [] : await firestore.getAll(
      ...page.docs.flatMap((document) => [
        firestore.doc(
          `companies/${options.companyId}/${STATE_COLLECTION}/${document.id}`,
        ),
        firestore.doc(
          `companies/${options.companyId}/${SEARCH_COLLECTION}/${document.id}`,
        ),
      ]),
    );
    for (let indexValue = 0; indexValue < page.docs.length; indexValue += 1) {
      const document = page.docs[indexValue];
      scanned += 1;
      try {
        const data = document.data();
        const schemaVersion = data.schemaVersion;
        if (typeof schemaVersion === "number" &&
            schemaVersion > FINANCIAL_LEDGER_SCHEMA_VERSION) {
          throw new Error(`Unsupported future schemaVersion ${schemaVersion}.`);
        }
        const originalKeys = validateOriginalQueryKeys(data.queryKeys);
        const queryKeys = compactKeysFromLedger(data);
        const afterData = {
          ...data,
          schemaVersion: FINANCIAL_LEDGER_SCHEMA_VERSION,
          queryKeys,
        };
        const projection = buildLedgerDerivedProjection(document.id, afterData);
        const state = stateSnapshots[indexValue * 2];
        const search = stateSnapshots[indexValue * 2 + 1];
        const stateFingerprint = state.exists
          ? stringValue(state.data()?.fingerprint)
          : "";
        const searchFingerprint = search.exists
          ? stringValue(search.data()?.fingerprint)
          : "";
        const mainNeedsUpdate = schemaVersion !== FINANCIAL_LEDGER_SCHEMA_VERSION ||
          !arraysEqual(originalKeys, queryKeys);
        const projectionNeedsUpdate = stateFingerprint !== projection.fingerprint ||
          searchFingerprint !== projection.fingerprint;
        if (!mainNeedsUpdate && !projectionNeedsUpdate) continue;
        const previousTargets = projectionTargetUpperBound(state.data() ?? {});
        const nextTargets = projection.queryKeys.length * (projection.salesRepId ? 2 : 1);
        const estimatedWriteUpperBound = (mainNeedsUpdate ? 1 : 0) +
          (projectionNeedsUpdate ? previousTargets + nextTargets + 2 : 0);
        const searchPath = `companies/${options.companyId}/${SEARCH_COLLECTION}/${document.id}`;
        plans.push({
          id: document.id,
          path: document.ref.path,
          ref: document.ref,
          updateTime: document.updateTime,
          queryKeys,
          searchTokenCount: projection.searchTokens.length,
          oldKeyCount: originalKeys.length,
          mainNeedsUpdate,
          projectionNeedsUpdate,
          estimatedWriteUpperBound,
          current: estimateComposite(document.ref.path, data, OLD_LEDGER_INDEXES),
          proposedMain: estimateComposite(document.ref.path, afterData, manifest.main),
          proposedSearch: estimateComposite(
            searchPath,
            projection.searchDocument,
            manifest.search,
          ),
        });
      } catch (error) {
        invalid.push({
          path: document.ref.path,
          reason: error instanceof Error ? error.message : String(error),
        });
      }
    }
    cursor = page.docs.at(-1);
    if (page.size < options.pageSize) break;
  } while (cursor);
  return {scanned, plans, invalid};
}

function compactKeysFromLedger(data: DocumentData): string[] {
  const type = requiredStoredString(data.type, "type");
  const customerId = optionalStoredString(data.customerId, "customerId");
  const paymentMethod = optionalStoredString(data.paymentMethod, "paymentMethod");
  const accountKeys = Array.isArray(data.accountKeys)
    ? data.accountKeys.map((value, indexValue) =>
      requiredStoredString(value, `accountKeys[${indexValue}]`))
    : [
      requiredStoredString(data.debitAccountKey, "debitAccountKey"),
      requiredStoredString(data.creditAccountKey, "creditAccountKey"),
    ];
  return buildLedgerQueryKeys({type, accountKeys, customerId, paymentMethod});
}

async function applyPlans(
  firestore: Firestore,
  companyId: string,
  plans: MigrationPlan[],
): Promise<void> {
  const mainPlans = plans.filter((plan) => plan.mainNeedsUpdate);
  for (let offset = 0; offset < mainPlans.length; offset += 400) {
    const batch = firestore.batch();
    for (const plan of mainPlans.slice(offset, offset + 400)) {
      batch.update(
        plan.ref,
        {
          queryKeys: plan.queryKeys,
          schemaVersion: FINANCIAL_LEDGER_SCHEMA_VERSION,
        },
        {lastUpdateTime: plan.updateTime},
      );
    }
    await batch.commit();
  }
  for (const plan of plans.filter((value) => value.projectionNeedsUpdate)) {
    await reconcileFinancialLedgerProjection(firestore, companyId, plan.id);
  }
}

function readAndValidateManifest(): {
  main: IndexDefinition[];
  search: IndexDefinition[];
  mainQueryKeysExempt: boolean;
  searchTokensExempt: boolean;
  searchQueryKeysExempt: boolean;
} {
  const manifestPath = resolve(__dirname, "../../../firestore.indexes.json");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as {
    indexes?: IndexDefinition[];
    fieldOverrides?: Array<{collectionGroup?: string; fieldPath?: string; indexes?: unknown[]}>;
  };
  if (!Array.isArray(manifest.indexes) || !Array.isArray(manifest.fieldOverrides)) {
    throw new Error(`Invalid index manifest: ${manifestPath}`);
  }
  const main = manifest.indexes.filter((value) => value.collectionGroup === LEDGER_COLLECTION);
  const search = manifest.indexes.filter((value) => value.collectionGroup === SEARCH_COLLECTION);
  const metricIndexes = main.filter((value) =>
    value.fields.some((field) => field.fieldPath.startsWith("metric")));
  if (main.length !== 4 || search.length !== 2 || metricIndexes.length !== 0) {
    throw new Error(
      "Ledger index manifest must contain exactly four main, two search, and zero metric composites.",
    );
  }
  const exempt = (collectionGroup: string, fieldPath: string): boolean =>
    manifest.fieldOverrides!.some((value) =>
      value.collectionGroup === collectionGroup &&
      value.fieldPath === fieldPath &&
      Array.isArray(value.indexes) && value.indexes.length === 0);
  const result = {
    main,
    search,
    mainQueryKeysExempt: exempt(LEDGER_COLLECTION, "queryKeys"),
    searchTokensExempt: exempt(SEARCH_COLLECTION, "searchTokens"),
    searchQueryKeysExempt: exempt(SEARCH_COLLECTION, "queryKeys"),
  };
  if (!result.mainQueryKeysExempt || !result.searchTokensExempt ||
      !result.searchQueryKeysExempt) {
    throw new Error("Ledger array fields must have explicit single-field exemptions.");
  }
  return result;
}

function estimateComposite(
  documentPath: string,
  data: DocumentData,
  indexes: IndexDefinition[],
): CompositeEstimate {
  const result: CompositeEstimate = {entries: 0, bytes: 0, largestEntryBytes: 0};
  const documentBytes = documentNameSize(documentPath);
  const parentBytes = documentNameSize(documentPath.split("/").slice(0, -2).join("/"));
  for (const definition of indexes) {
    const arrayField = definition.fields.find((field) => field.arrayConfig === "CONTAINS");
    if (!arrayField) throw new Error("Ledger composites must have exactly one array field.");
    const array = fieldValue(data, arrayField.fieldPath);
    if (!Array.isArray(array)) continue;
    const otherValues: unknown[] = [];
    let complete = true;
    for (const field of definition.fields) {
      if (field === arrayField) continue;
      const value = fieldValue(data, field.fieldPath);
      if (value === undefined) {
        complete = false;
        break;
      }
      otherValues.push(value);
    }
    if (!complete) continue;
    const base = documentBytes + parentBytes + 32 + otherValues.reduce<number>(
      (sum, value) => sum + indexedValueSize(value),
      0,
    );
    for (const item of array) {
      const entryBytes = base + indexedValueSize(item);
      result.entries += 1;
      result.bytes += entryBytes;
      result.largestEntryBytes = Math.max(result.largestEntryBytes, entryBytes);
    }
  }
  return result;
}

function fieldValue(data: DocumentData, path: string): unknown {
  let value: unknown = data;
  for (const part of path.split(".")) {
    if (!isPlainMap(value) || !(part in value)) return undefined;
    value = value[part];
  }
  return value;
}

function indexedValueSize(value: unknown): number {
  return Math.min(fieldValueSize(value), MAX_INDEXED_VALUE_BYTES);
}

function fieldValueSize(value: unknown): number {
  if (value === null || value === undefined) return 1;
  if (typeof value === "string") return stringSize(value);
  if (typeof value === "boolean") return 1;
  if (typeof value === "number" || typeof value === "bigint") return 8;
  if (value instanceof Timestamp || value instanceof Date) return 8;
  if (value instanceof Uint8Array) return value.byteLength;
  if (Array.isArray(value)) return value.reduce((sum, item) => sum + fieldValueSize(item), 0);
  if (isPlainMap(value)) {
    return Object.entries(value).reduce(
      (sum, [name, item]) => sum + stringSize(name) + fieldValueSize(item),
      32,
    );
  }
  return 1;
}

function isPlainMap(value: unknown): value is DocumentData {
  return typeof value === "object" && value !== null &&
    !Array.isArray(value) && !(value instanceof Timestamp) &&
    !(value instanceof Uint8Array) && !(value instanceof DocumentReference);
}

function documentNameSize(path: string): number {
  if (!path) return 16;
  return path.split("/").reduce((sum, part) => sum + stringSize(part), 16);
}

function stringSize(value: string): number {
  return Buffer.byteLength(value, "utf8") + 1;
}

function validateOriginalQueryKeys(value: unknown): string[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new Error("queryKeys must be a non-empty array.");
  }
  if (value.length > MAX_LEGACY_QUERY_KEYS) {
    throw new Error(`queryKeys has ${value.length} elements; safety maximum is ${MAX_LEGACY_QUERY_KEYS}.`);
  }
  return value.map((item, indexValue) => {
    if (typeof item !== "string" || item.length === 0) {
      throw new Error(`queryKeys[${indexValue}] must be a non-empty scalar string.`);
    }
    return item;
  });
}

function projectionTargetUpperBound(data: DocumentData): number {
  if (!Array.isArray(data.queryKeys)) return 0;
  const validKeys = data.queryKeys.filter((value) => typeof value === "string").length;
  return validKeys * (stringValue(data.salesRepId) ? 2 : 1);
}

function requiredStoredString(value: unknown, field: string): string {
  const result = optionalStoredString(value, field);
  if (!result) throw new Error(`${field} must be a non-empty scalar string.`);
  return result;
}

function optionalStoredString(value: unknown, field: string): string {
  if (value === undefined || value === null) return "";
  if (typeof value !== "string") throw new Error(`${field} must be a scalar string.`);
  const result = value.trim();
  if (Buffer.byteLength(result, "utf8") > 1_500) {
    throw new Error(`${field} exceeds 1,500 bytes.`);
  }
  return result;
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function arraysEqual(left: string[], right: string[]): boolean {
  return left.length === right.length && left.every((value, indexValue) =>
    value === right[indexValue]);
}

function totalEstimate(values: CompositeEstimate[]): CompositeEstimate {
  return values.reduce(addEstimates, {entries: 0, bytes: 0, largestEntryBytes: 0});
}

function addEstimates(
  left: CompositeEstimate,
  right: CompositeEstimate,
): CompositeEstimate {
  return {
    entries: left.entries + right.entries,
    bytes: left.bytes + right.bytes,
    largestEntryBytes: Math.max(left.largestEntryBytes, right.largestEntryBytes),
  };
}

function keyStats(values: number[]): {minimum: number; maximum: number; total: number} {
  return {
    minimum: values.length === 0 ? 0 : Math.min(...values),
    maximum: values.length === 0 ? 0 : Math.max(...values),
    total: values.reduce((sum, value) => sum + value, 0),
  };
}

function percentageReduction(before: number, after: number): number {
  return before === 0 ? 0 : Math.round((1 - after / before) * 100_000) / 1_000;
}

function index(fields: IndexField[]): IndexDefinition {
  return {collectionGroup: LEDGER_COLLECTION, queryScope: "COLLECTION", fields};
}

function contains(fieldPath: string): IndexField {
  return {fieldPath, arrayConfig: "CONTAINS"};
}

function ascending(fieldPath: string): IndexField {
  return {fieldPath, order: "ASCENDING"};
}

function descending(fieldPath: string): IndexField {
  return {fieldPath, order: "DESCENDING"};
}

function validateApplyOptions(options: Options): void {
  if (!options.apply) return;
  if (options.confirmProject !== options.projectId ||
      options.confirmCompany !== options.companyId) {
    throw new Error("Apply mode requires exact --confirm-project and --confirm-company values.");
  }
}

function parseOptions(args: string[]): Options {
  const values = new Map<string, string>();
  let apply = false;
  const allowed = new Set([
    "project", "company", "confirm-project", "confirm-company", "page-size", "max-writes",
  ]);
  for (const arg of args) {
    if (arg === "--apply") {
      apply = true;
      continue;
    }
    const match = /^--([^=]+)=(.*)$/.exec(arg);
    if (!match || !allowed.has(match[1])) throw new Error(`Unknown argument: ${arg}`);
    values.set(match[1], match[2]);
  }
  const projectId = values.get("project") ?? "";
  const companyId = values.get("company") ?? "";
  if (!projectId || !companyId) throw new Error("--project and --company are required.");
  const pageSize = positiveInteger(values.get("page-size") ?? "250", "page-size");
  const maxWrites = positiveInteger(values.get("max-writes") ?? "500", "max-writes");
  if (pageSize > 1_000) throw new Error("--page-size must not exceed 1000.");
  return {
    projectId,
    companyId,
    apply,
    confirmProject: values.get("confirm-project") ?? "",
    confirmCompany: values.get("confirm-company") ?? "",
    pageSize,
    maxWrites,
  };
}

function positiveInteger(value: string, name: string): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error(`--${name} must be a positive integer.`);
  }
  return parsed;
}

void main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.stack : String(error)}\n`);
  process.exitCode = 1;
});
