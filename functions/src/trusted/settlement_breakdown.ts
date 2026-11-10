import {DocumentReference, DocumentSnapshot, FieldPath, Firestore, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {requireTrustedUser} from "./common";
import {cashBalanceDocumentId} from "./cash_ledger";
import {assertSettlementRecoveryEmulator, prepareCommittedSettlementRecovery} from "./settlement_journal_persistence";
import {Time, compare, freeze, id, required, time} from "./settlement_preflight_shared";
import {settlementEvidenceDigest as digest, settlementInventoryEvidenceDigest as inventoryDigest} from "./settlement_pending_evidence";
import {analyzeSettlementSourceEvidence, BreakdownIssue, CashEvidenceDocument, CASH_SOURCE_COLLECTIONS} from "./settlement_source_evidence";
import {settlementReadStage, settlementReadStageSync} from "./settlement_read_profile";
import {SettlementReadTarget, assertApprovedSettlementReadTarget, assertSettlementReadTransaction} from "./settlement_read_target";

export interface SettlementBreakdownRequest {
  companyId: string; salesRepId: string;
  /** Exactly one mode. Settlement cutoffs use actual SDK commit metadata. */
  settlementId?: string; committedThrough?: Time;
}
export interface SettlementBreakdownOptions {
  enableEmulatorBreakdown?: boolean;
  readTarget?: SettlementReadTarget;
  /** Internal resource controls may lower ceilings; never establish authority. */
  pageSize?: number; readBudget?: number;
  /** A transport can lower, never increase, the internal retry ceiling. */
  maximumAttempts?: number;
}
export const SETTLEMENT_BREAKDOWN_LIMITS = Object.freeze({pageSize: 128, maximumPageSize: 256, inventoryDocuments: 16000,
  documentGets: 64, queries: 256, referencesPerSource: 2048, documentBytes: 65536, attemptBytes: 33554432, attemptMilliseconds: 45000});

// Explicit projections avoid loading invoice items/search payloads. These are
// current source witnesses; no mutable source is presented as its old snapshot.
const sourceFields = ["id", "companyId", "status", "invoiceStatus", "financialPosted", "financialPostedAt", "financialPostedByUid", "financialPostedByName",
  "paymentMethod", "paymentType", "amount", "grandTotal", "initialPaidAmount", "initialCashAccount", "cashMovementIds", "customerId",
  "createdByUid", "createdByName", "createdByRole", "salesRepId", "salesRepName", "receiptIds", "cancelledReceiptIds", "returnInvoiceIds",
  "invoiceAllocations", "invoiceAllocationDetails", "cancellationCashMovementIds", "cancellationVersion", "cancelledByUid", "cancelledByName", "cancelledByRole", "cancelledAt",
  "originalInvoiceId", "cashRefundAmount", "refundType", "fundingSource", "cashMovementId", "approvedByUid", "approvedByName", "approvedByRole", "approvedAt",
  "repMovementId", "companyMovementId", "sourceCashAccount", "sourceCashAccountId", "destinationCashAccount", "destinationCashAccountId",
  "settlementDate", "postedByUid", "postedByName", "postedByRole", "sourceCreatedByUid", "sourceCreatedByName", "sourceCreatedByRole", "accounting", "settlementNumber",
  "invoiceNumber", "invoiceDate", "receiptNumber", "receiptDate", "returnNumber", "returnDate", "expenseDate", "currency", "moneyScale", "createdAt", "postedAt"];
const movementFields = ["id", "companyId", "cashAccount", "salesRepId", "salesRepName", "cashAccountSalesRepId", "holderType", "holderUid", "treasuryAccountId",
  "currency", "moneyScale", "movementType", "type", "direction", "amount", "balanceBefore", "balanceAfter", "date", "movementDate", "createdAt",
  "sourceCollection", "sourceId", "sourceNumber", "referenceId", "referenceNumber", "customerId", "counterpartMovementId", "accounting",
  "originalCollectionSourceIds", "reversesMovementId", "isReversal", "immutable", "createdByUid", "createdByName", "createdByRole", "paymentType",
  "sellerId", "sellerName", "collectorUid", "collectorName", "postedByUid", "postedByName", "postedByRole", "sourceCreatedByUid", "sourceCreatedByName", "sourceCreatedByRole"];

/** Internal only. Every collection is paged to its end in ONE read-only SDK
 * snapshot. An exhausted budget or lost snapshot never clears partial totals. */
export async function settlementBreakdownTransaction(
  db: Firestore, viewerUid: string | undefined, input: SettlementBreakdownRequest, options: SettlementBreakdownOptions = {},
) {
  if (options.readTarget) assertApprovedSettlementReadTarget(db, options.readTarget, input?.companyId);
  else {
    if (options.enableEmulatorBreakdown !== true) throw new HttpsError("failed-precondition", "Settlement breakdown is disabled by default.");
    assertSettlementRecoveryEmulator(db);
  }
  if (!viewerUid) throw new HttpsError("unauthenticated", "Authentication required.");
  id(viewerUid, "Viewer UID");
  const request = captureRequest(input);
  const maximumAttempts = options.maximumAttempts ?? 5;
  if (!Number.isInteger(maximumAttempts) || maximumAttempts < 1 || maximumAttempts > 5) throw new HttpsError("invalid-argument", "Invalid attempt bound.");
  const pageSize = options.pageSize ?? SETTLEMENT_BREAKDOWN_LIMITS.pageSize, readBudget = options.readBudget ?? SETTLEMENT_BREAKDOWN_LIMITS.inventoryDocuments;
  if (!Number.isInteger(pageSize) || pageSize < 16 || pageSize > SETTLEMENT_BREAKDOWN_LIMITS.maximumPageSize ||
    !Number.isInteger(readBudget) || readBudget < 1 || readBudget > SETTLEMENT_BREAKDOWN_LIMITS.inventoryDocuments)
    throw new HttpsError("invalid-argument", "Bounded page size and inventory read budget required.");
  for (let attempt = 0; ; attempt++) {
    try {
      const result = await db.runTransaction(async raw => {
        const transactionDb = Reflect.get(raw, "_firestore");
        if (!transactionDb) throw new HttpsError("failed-precondition", "A supported isolated SDK transaction is required.");
        if (options.readTarget) assertSettlementReadTransaction(raw, db, options.readTarget);else assertSettlementRecoveryEmulator(transactionDb);
        const reader = boundedReader(raw, db, request.companyId, pageSize, readBudget);
        const user = await requireTrustedUser(reader.tx, db, viewerUid, request.companyId);
        if (user.role !== "admin") throw new HttpsError("permission-denied", "Only company administrators can inspect settlement cash evidence.");
        const profile = required(await reader.get(`users/${viewerUid}`));
        if (profile.uid !== undefined && profile.uid !== viewerUid) throw new HttpsError("permission-denied", "Viewer profile identity differs.");
        const c = `companies/${request.companyId}`, companySnapshot = await reader.get(c), company = required(companySnapshot);
        if (company.id !== request.companyId || company.active !== true || company.companyId !== undefined && company.companyId !== request.companyId)
          throw new HttpsError("permission-denied", "Company is inactive or its identity differs.");
        const repSnapshot = await reader.get(`users/${request.salesRepId}`), representative = required(repSnapshot);
        if (representative.companyId !== request.companyId || representative.role !== "sales_rep" || representative.uid !== undefined && representative.uid !== request.salesRepId)
          throw new HttpsError("permission-denied", "Representative does not belong to this company.");
        // Historical rep eligibility may change; current viewer authority may not.
        const target = request.settlementId ? await reader.get(`${c}/settlements/${request.settlementId}`) : undefined;
        const targetData = target ? required(target) : undefined;
        if (targetData && (targetData.companyId !== request.companyId || targetData.id !== request.settlementId || targetData.salesRepId !== request.salesRepId || targetData.status !== "posted"))
          throw new HttpsError("failed-precondition", "Settlement scope/status differs.");
        const cutoff = target ? time(target.createTime) : request.committedThrough!;
        if (compare(cutoff, time(companySnapshot.readTime)) > 0) throw new HttpsError("invalid-argument", "Cash cutoff exceeds the SDK observation time.");
        const issues: BreakdownIssue[] = [];
        const issue = (code: string, path: string, message: string) => {issues.push({code, path, message});};
        const bookId = id(targetData?.accounting?.bookId ?? company.activeBookId, "Evidence book"), b = `${c}/books/${bookId}`;
        const bookSnapshot = await reader.get(b), book = required(bookSnapshot);
        if (book.id !== bookId || book.companyId !== request.companyId || book.bookId !== undefined && book.bookId !== bookId ||
          book.approvalStatus !== "approved" || book.journalPostingEnabled !== false || book.moneyScale !== 3 || !/^[A-Z]{3}$/.test(book.currency))
          throw new HttpsError("failed-precondition", "Explicit approved scale-3 evidence book with posting disabled is required.");
        const lock = await reader.get(`${c}/maintenance_locks/cash_reconciliation`);
        if (lock.exists && lock.data()?.active !== false) issue("reconciliation_in_progress", lock.ref.path, "Cash reconciliation lock is active or malformed.");
        let bindingSnapshot: DocumentSnapshot | undefined;
        if (book.cashEvidenceCurrencyBindingId !== undefined) {
          bindingSnapshot = await reader.get(`${b}/currency_bindings/${id(book.cashEvidenceCurrencyBindingId, "Cash currency binding")}`);
          const binding = bindingSnapshot.data();
          if (!binding || compare(time(bindingSnapshot.createTime), time(bindingSnapshot.updateTime)) !== 0 ||
            binding.id !== bindingSnapshot.id || binding.companyId !== request.companyId || binding.bookId !== bookId || binding.revisionId !== bindingSnapshot.id ||
            binding.approvalStatus !== "approved" || binding.sourceCollection !== "cash_movements" || binding.scope !== "company_cash_ledger" ||
            binding.currency !== book.currency || binding.moneyScale !== 3) {
            issue("invalid_cash_currency_binding", bindingSnapshot.ref.path, "A company-ledger currency binding is missing or inconsistent.");bindingSnapshot = undefined;
          }
        }
        const documents: CashEvidenceDocument[] = [];
        for (const collection of CASH_SOURCE_COLLECTIONS) {
          const scanned = await settlementReadStage("sourceScans", () => reader.scan(`${c}/${collection}`, collection === "cash_movements" ? movementFields : sourceFields));
          if (!reader.complete(collection)) {
            issue("inventory_bound_exceeded", `${c}/${collection}`, "Complete inventory exceeds its document/query/time budget; no partial reconstruction is certified.");
            return finish({status: "blocked" as const, totals: null, opening: {state: "not_evaluated_incomplete_coverage", amountUnits: null},
              carry: {state: "unverifiable_incomplete_coverage", amountUnits: null},
              issueCount: issues.length, issues, coverage: {inventory: "incomplete_bound_exceeded", unknownOpeningAssumedZero: false},
              allocation: {status: "not_implemented", settlementSourceAllocations: null}}, request, cutoff, book.currency, bookId, reader, companySnapshot);
          }
          documents.push(...scanned.map(evidenceDocument));
        }
        const balanceSnapshots = await Promise.all([cashBalanceDocumentId("rep_cash", request.salesRepId), "company_cash"].map(key => reader.get(`${c}/cash_balances/${key}`)));
        const legacy = [...documents.filter(d => d.path.startsWith(`${c}/cash_movements/`)), ...balanceSnapshots.filter(s => s.exists).map(evidenceDocument)]
          .filter(d => d.data.currency === undefined || d.data.moneyScale === undefined);
        let legacyCurrencyBound = bindingSnapshot !== undefined;
        if (bindingSnapshot && legacy.some(d => compare(time(bindingSnapshot!.createTime), d.createTime) > 0)) {
          legacyCurrencyBound = false;issue("late_currency_binding", bindingSnapshot.ref.path, "Currency witness postdates legacy cash evidence.");
        }
        // Reuse the durable atomic recovery validator in THIS read-only snapshot.
        // Legacy settlements remain cash evidence, never implicitly journalized.
        let accountingEvidence: "validated_atomic_envelope" | "legacy_cash_only" | "not_applicable" = target ? "legacy_cash_only" : "not_applicable";
        if (targetData?.accounting) {
          try {
            await settlementReadStage("atomicRecovery", () => prepareCommittedSettlementRecovery(reader.tx, db, viewerUid, {companyId: request.companyId,
              salesRepId: request.salesRepId, idempotencyKey: targetData.idempotencyKey, amount: targetData.amount,
              settlementDate: time(targetData.settlementDate), notes: targetData.notes}, undefined, options.readTarget));
            accountingEvidence = "validated_atomic_envelope";
          } catch (error) {
            if (!(error instanceof HttpsError) || ["permission-denied", "unauthenticated"].includes(error.code)) throw error;
            issue("atomic_accounting_evidence", target!.ref.path, error.message);
          }
        }
        const result = settlementReadStageSync("reconciliation", () => analyzeSettlementSourceEvidence({companyId: request.companyId, salesRepId: request.salesRepId,
          cutoff, settlementId: request.settlementId ?? null, currency: book.currency, documents,
          balances: balanceSnapshots.filter(s => s.exists).map(evidenceDocument), legacyCurrencyBound, initialIssues: issues, validationProfile: "paged_v1"}));
        if (reader.elapsed() > SETTLEMENT_BREAKDOWN_LIMITS.attemptMilliseconds) throw new HttpsError("resource-exhausted", "Evidence verification time budget exceeded.");
        return finish({...result, accountingEvidence, configurationEvidence: {
          book: {path: b, createTime: time(bookSnapshot.createTime), updateTime: time(bookSnapshot.updateTime), versionAfterCutoff: compare(time(bookSnapshot.updateTime), cutoff) > 0},
          legacyCashCurrencyBound: legacyCurrencyBound, currencyBinding: bindingSnapshot ? {path: bindingSnapshot.ref.path, revisionId: bindingSnapshot.id,
            createTime: time(bindingSnapshot.createTime), updateTime: time(bindingSnapshot.updateTime)} : null,
        }}, request, cutoff, book.currency, bookId, reader, companySnapshot);
      }, {readOnly: true});
      // Financial pages stay on their original snapshot. Recheck only present
      // viewing authority before delivery; a mid-scan revocation must not leak
      // the completed historical report under an old authorization snapshot.
      const authority = await currentAuthority(db, viewerUid, request, options.readTarget);
      if (compare(authority, result.observation.readTime) < 0) throw new HttpsError("data-loss", "Present viewing authority predates the financial snapshot.");
      return freeze({...result, observation: {...result.observation, attempt: attempt + 1,
        authorizationReadTime: authority, authorizationDocumentGets: 3}});
    } catch (error) {
      const failure = error as {code?: unknown; details?: unknown; message?: unknown};
      if (attempt >= maximumAttempts - 1 || !(failure.code === 10 || failure.code === 3 && (failure.details === "Transaction is invalid or closed." || failure.message === "3 INVALID_ARGUMENT: Transaction is invalid or closed."))) throw error;
    }
  }
}

export type SettlementCashBreakdown = Awaited<ReturnType<typeof settlementBreakdownTransaction>>;

async function currentAuthority(db: Firestore, uid: string, request: SettlementBreakdownRequest, readTarget?: SettlementReadTarget): Promise<Time> {
  return db.runTransaction(async raw => {
    const actual = Reflect.get(raw, "_firestore");
    if (!actual) throw new HttpsError("failed-precondition", "Supported isolated transaction required.");
    if (readTarget) assertSettlementReadTransaction(raw, db, readTarget);else assertSettlementRecoveryEmulator(actual);
    const reader = boundedReader(raw, db, request.companyId, SETTLEMENT_BREAKDOWN_LIMITS.pageSize, SETTLEMENT_BREAKDOWN_LIMITS.inventoryDocuments);
    const user = await requireTrustedUser(reader.tx, db, uid, request.companyId);
    const [profile, company, rep] = await Promise.all([reader.get(`users/${uid}`), reader.get(`companies/${request.companyId}`), reader.get(`users/${request.salesRepId}`)]);
    const p = required(profile), c = required(company), r = required(rep);
    if (user.role !== "admin" || p.uid !== undefined && p.uid !== uid || c.id !== request.companyId || c.active !== true ||
      c.companyId !== undefined && c.companyId !== request.companyId || r.companyId !== request.companyId || r.role !== "sales_rep" || r.uid !== undefined && r.uid !== request.salesRepId)
      throw new HttpsError("permission-denied", "Current company viewing authority was revoked or changed.");
    return time(company.readTime);
  }, {readOnly: true});
}

function captureRequest(input: SettlementBreakdownRequest): SettlementBreakdownRequest {
  if (!input || Object.keys(input).some(k => !["companyId", "salesRepId", "settlementId", "committedThrough"].includes(k)) ||
    (input.settlementId === undefined) === (input.committedThrough === undefined)) throw new HttpsError("invalid-argument", "Select exactly one settlement or committed-through cutoff.");
  return freeze({companyId: id(input.companyId, "Company"), salesRepId: id(input.salesRepId, "Representative"),
    ...(input.settlementId === undefined ? {committedThrough: time(input.committedThrough)} : {settlementId: id(input.settlementId, "Settlement")})});
}
function evidenceDocument(s: DocumentSnapshot): CashEvidenceDocument {
  return {path: s.ref.path, id: s.id, data: s.data()!, createTime: time(s.createTime), updateTime: time(s.updateTime)};
}
function finish<T extends {issues: BreakdownIssue[]}>(result: T, request: SettlementBreakdownRequest, cutoff: Time, currency: string,
  bookId: string, reader: ReturnType<typeof boundedReader>, observation: DocumentSnapshot) {
  // The larger read-only inventory profile shares the existing canonical
  // implementation. Stored pending/journal hashes keep their strict profile.
  // SDK observation clocks and physical page boundaries are not economics.
  const data = result as T & {movements?: unknown[]; excludedMovements?: unknown[]};
  const {movements = [], excludedMovements = [], ...summary} = data;
  const evidenceDigest = settlementReadStageSync("evidenceDigest", () => inventoryDigest({schemaVersion: 2, request, cutoff, currency, bookId, summary,
    movementDigests: movements.map(inventoryDigest), excludedMovementDigests: excludedMovements.map(inventoryDigest)}));
  return freeze({schemaVersion: 2 as const, mode: "settlement_cash_source_evidence" as const,
    companyId: request.companyId, salesRepId: request.salesRepId, settlementId: request.settlementId ?? null,
    cutoff: {basis: "sdk_commit_order" as const, inclusiveThrough: cutoff}, currency, moneyScale: 3 as const, bookId,
    ...result, evidenceDigest, snapshotCoverage: reader.coverage(), observation: {readTime: time(observation.readTime), documentGets: reader.getCount(),
      queryCount: reader.queryCount(), scannedDocuments: reader.scannedCount(), payloadBytes: reader.bytesCount(), elapsedMilliseconds: reader.elapsed(),
      pageSize: reader.pageSize, readBudget: reader.readBudget, limits: SETTLEMENT_BREAKDOWN_LIMITS},
    // Server-only transport witness. Never included in public detail pages.
    readWitness: reader.readWitness()});
}
interface CoveragePage {collection: string; afterId: string | null; firstId: string | null; lastId: string | null; count: number;
  readTime: Time; witnessDigest: string; terminal: boolean}
function boundedReader(raw: Transaction, db: Firestore, companyId: string, pageSize: number, readBudget: number) {
  const cache = new Map<string, DocumentSnapshot>(), completeCollections = new Set<string>(), pages: CoveragePage[] = [];
  const versions = new Map<string, DocumentSnapshot>();
  const counts: {collection: string; count: number; limit: number; readTime: Time}[] = [];
  let queries = 0, scanned = 0, bytes = 0, snapshotTime: Time | undefined;
  let incompleteReason: "document_budget" | "query_budget" | "time_budget" | null = null;const started = Date.now();
  const exhausted = () => {
    if (queries >= SETTLEMENT_BREAKDOWN_LIMITS.queries) {incompleteReason = "query_budget";return true;}
    if (Date.now() - started > SETTLEMENT_BREAKDOWN_LIMITS.attemptMilliseconds) {incompleteReason = "time_budget";return true;}
    return false;
  };
  const sameTime = (value: unknown) => {
    const stamp = time(value);
    if (snapshotTime && compare(stamp, snapshotTime) !== 0) throw new HttpsError("data-loss", "Evidence pages do not share the original SDK snapshot.");
    snapshotTime ??= stamp;return stamp;
  };
  const inspectSize = (snapshots: DocumentSnapshot[]) => {
    for (const s of snapshots) {
      versions.set(s.ref.path, s);
      sameTime(s.readTime);
      if (s.exists && (compare(time(s.createTime), snapshotTime!) > 0 || compare(time(s.updateTime), snapshotTime!) > 0))
        throw new HttpsError("data-loss", "Document version exceeds the shared snapshot.");
      const size = Buffer.byteLength(JSON.stringify(s.data() ?? null), "utf8");bytes += size;
      if (size > SETTLEMENT_BREAKDOWN_LIMITS.documentBytes || bytes > SETTLEMENT_BREAKDOWN_LIMITS.attemptBytes)
        throw new HttpsError("resource-exhausted", "Source evidence exceeds document/attempt payload bound.");
    }
  };
  const getAll = async (refs: DocumentReference[]) => {
    if (Date.now() - started > SETTLEMENT_BREAKDOWN_LIMITS.attemptMilliseconds) throw new HttpsError("resource-exhausted", "Evidence attempt time budget exceeded.");
    if (refs.some(r => !(r.path === `companies/${companyId}` || r.path.startsWith(`companies/${companyId}/`) || /^users\/[^/]+$/.test(r.path))))
      throw new HttpsError("failed-precondition", "Cross-company evidence read rejected.");
    const missing = [...new Map(refs.filter(r => !cache.has(r.path)).map(r => [r.path, r])).values()];
    if (cache.size + missing.length > SETTLEMENT_BREAKDOWN_LIMITS.documentGets) throw new HttpsError("resource-exhausted", "Evidence document read budget exceeded.");
    if (missing.length) {const received = await raw.getAll(...missing);inspectSize(received);for (const snapshot of received) cache.set(snapshot.ref.path, snapshot);}
    return refs.map(r => cache.get(r.path)!);
  };
  const get = async (path: string) => (await getAll([db.doc(path)]))[0];
  const scan = async (path: string, fields: string[]) => {
    const collection = CASH_SOURCE_COLLECTIONS.find(collection => path === `companies/${companyId}/${collection}`);
    if (!collection || completeCollections.has(collection)) throw new HttpsError("failed-precondition", "Unplanned/repeated evidence collection scan.");
    const received: DocumentSnapshot[] = [];let cursor: DocumentSnapshot | undefined;
    if (exhausted()) return received;
    // Bounded independent cardinality witness catches skipped pages/documents,
    // including sources that have no cash leg. Limit prevents an aggregate from
    // scanning arbitrarily more index entries than this attempt can inventory.
    const countLimit = Math.max(1, readBudget - scanned + 1);queries++;
    const cardinality = await raw.get(db.collection(path).limit(countLimit).count()), countTime = sameTime(cardinality.readTime), count = cardinality.data().count;
    if (!Number.isSafeInteger(count) || count < 0 || count > countLimit) throw new HttpsError("data-loss", "Invalid bounded coverage cardinality.");
    counts.push({collection, count, limit: countLimit, readTime: countTime});
    if (count > readBudget - scanned) {incompleteReason = "document_budget";return received;}
    for (;;) {
      if (exhausted()) return received;
      const limit = Math.min(pageSize, Math.max(1, readBudget - scanned + 1));
      let query = db.collection(path).select(...fields).orderBy(FieldPath.documentId()).limit(limit);
      if (cursor) query = query.startAfter(cursor);
      queries++;const result = await raw.get(query), readTime = sameTime(result.readTime);inspectSize(result.docs);scanned += result.size;
      if (result.size !== result.docs.length || result.size > limit) throw new HttpsError("data-loss", "Invalid evidence page size.");
      let previous = cursor?.id, witnessDigest = digest(["cash-coverage-page-v1", path]);
      for (const doc of result.docs) {
        if (doc.ref.parent.path !== path || previous !== undefined && Buffer.compare(Buffer.from(previous), Buffer.from(doc.id)) >= 0)
          throw new HttpsError("data-loss", "Evidence cursor repeated, skipped backwards or crossed company scope.");
        const cached = cache.get(doc.ref.path);
        if (cached?.exists && compare(time(cached.updateTime), time(doc.updateTime)) !== 0) throw new HttpsError("data-loss", "Source changed within the shared snapshot.");
        witnessDigest = digest({previous: witnessDigest, id: doc.id, createTime: time(doc.createTime), updateTime: time(doc.updateTime)});previous = doc.id;
      }
      const terminal = result.size < limit;
      pages.push({collection, afterId: cursor?.id ?? null, firstId: result.docs[0]?.id ?? null, lastId: result.docs.at(-1)?.id ?? null,
        count: result.size, readTime, witnessDigest, terminal});
      if (scanned > readBudget) {incompleteReason = "document_budget";return received;}
      if (Date.now() - started > SETTLEMENT_BREAKDOWN_LIMITS.attemptMilliseconds) {incompleteReason = "time_budget";return received;}
      received.push(...result.docs);
      if (terminal) {
        if (received.length !== count) throw new HttpsError("data-loss", "Paged coverage differs from its independent snapshot count.");
        completeCollections.add(collection);return received;
      }
      cursor = result.docs.at(-1)!;
    }
  };
  const tx = new Proxy(raw, {get(target, prop) {
    if (["create", "set", "update", "delete"].includes(String(prop))) return () => {throw new HttpsError("failed-precondition", "Settlement source evidence cannot write.");};
    if (prop === "getAll") return (...refs: DocumentReference[]) => getAll(refs);
    if (prop === "get") return async (ref: DocumentReference) => {
      if (typeof ref?.path !== "string") throw new HttpsError("failed-precondition", "Only planned document reads are supported.");
      return (await getAll([ref]))[0];
    };
    const value = Reflect.get(target, prop);return typeof value === "function" ? value.bind(target) : value;
  }});
  return {tx, get, scan, pageSize, readBudget, complete: (collection: string) => completeCollections.has(collection),
    readWitness: () => [...versions.values()].map(s => ({path: s.ref.path, exists: s.exists,
      createTime: s.exists ? time(s.createTime) : null, updateTime: s.exists ? time(s.updateTime) : null})),
    coverage: () => {
      const manifest = {strategy: "document_id_pages_single_sdk_snapshot" as const, companyId, readTime: snapshotTime ?? null,
        complete: completeCollections.size === CASH_SOURCE_COLLECTIONS.length, incompleteReason, collections: [...completeCollections], pages, counts,
        scannedDocuments: scanned, pageSize, readBudget};
      return {...manifest, digest: inventoryDigest(manifest)};
    },
    getCount: () => cache.size, queryCount: () => queries, scannedCount: () => scanned, bytesCount: () => bytes, elapsed: () => Date.now() - started};
}
