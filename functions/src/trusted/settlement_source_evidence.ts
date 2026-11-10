import {DocumentData} from "firebase-admin/firestore";
import {cashBalanceDocumentId} from "./cash_ledger";
import {sumUnits} from "./exact_decimal";
import {Time, compare, money, time} from "./settlement_preflight_shared";
import {canonicalSettlementEvidence as canonical, settlementEvidenceDigest as digest, canonicalSettlementInventoryEvidence} from "./settlement_pending_evidence";

export interface CashEvidenceDocument {
  path: string; id: string; data: DocumentData; createTime: Time; updateTime: Time;
}
export interface BreakdownIssue {code: string; path: string; message: string}
export interface SettlementCashTotals {
  openingUnits: string; carryUnits: string; activitySinceCarryUnits: string; cashAvailableBeforeUnits: string;
  transferredUnits: string; remainingUnits: string; currentBalanceUnits: string;
}
export interface ActorEvidence {uid: string | null; name: string | null; role: string | null; basis: string}
export interface CashEvidenceRow {
  id: string; path: string; category: string; verification: "verified" | "blocked";
  cashAccount: "rep_cash" | "company_cash"; holderType: "representative" | "company"; holderUid: string;
  amountUnits: string; signedUnits: string; beforeUnits: string; afterUnits: string;
  committedAt: Time; recordedAt: Time; businessDate: Time;
  source: {collection: string; id: string; path: string; createTime: Time; updateTime: Time; versionAfterCutoff: boolean;
    recordedCreatedAt: Time | null; recordedPostedAt: Time | null; businessDate: Time | null};
  sourceNumber: string | null; movementCreator: ActorEvidence; sourceCreator: ActorEvidence;
  collector: ActorEvidence; postingActor: ActorEvidence;
  recordedProvenance: {sellerId: string | null; sellerName: string | null; collector: ActorEvidence; postedBy: ActorEvidence; sourceCreatedBy: ActorEvidence};
  recordedSalesRepId: string | null; originalSellers: {invoiceId: string; uid: string | null; name: string | null}[];
  receivableAllocations: {invoiceId: string; amountUnits: string}[];
  collectionMovementIds: string[]; reversesMovementId: string | null; counterpartMovementId: string | null;
  unallocatedReceiptUnits: string | null;
  referencedDocuments: {id: string; path: string; number: string | null; businessDate: Time | null;
    createTime: Time; updateTime: Time; role: string; versionAfterCutoff: boolean}[];
}
export const CASH_SOURCE_COLLECTIONS = ["cash_movements", "invoices", "receipts", "sales_returns", "expenses", "settlements"] as const;

class EvidenceProblem extends Error {
  constructor(readonly code: string, readonly path: string, message: string) {super(message);}
}
function check(ok: boolean, code: string, path: string, message: string): asserts ok {if (!ok) throw new EvidenceProblem(code, path, message);}
function units(value: unknown, path: string): bigint {
  try {return money(value);} catch {throw new EvidenceProblem("inexact_amount", path, "A resolved exact scale-3 amount is required.");}
}
function clock(value: unknown, path: string): Time {
  try {return time(value);} catch {throw new EvidenceProblem("missing_timestamp", path, "A resolved timestamp is required.");}
}
function identifier(value: unknown, path: string): string {
  check(typeof value === "string" && value.length > 0 && value.length <= 256 && value.trim() === value && !/[\\/\u0000-\u001f\u007f]/u.test(value) && value !== "." && value !== "..",
    "invalid_reference", path, "A bounded single identifier is required.");return value;
}
function text(value: unknown): string | null {return typeof value === "string" && value.trim() ? value.trim() : null;}
function referenceIds(value: unknown, path: string, maximum: number): string[] {
  check(Array.isArray(value) && value.length <= maximum, "reference_coverage", path, "Reference list is missing or exceeds its evidence bound.");
  const result = value.map(v => identifier(v, path));
  check(new Set(result).size === result.length, "duplicate_reference", path, "Reference IDs must be unique.");return result;
}
function evidenceEqual(actual: unknown, expected: unknown, path: string, message: string, encode: (value: unknown) => string): void {
  let same: boolean;
  try {same = encode(actual) === encode(expected);} catch {throw new EvidenceProblem("malformed_evidence", path, "Evidence fields exceed the bounded canonical contract.");}
  check(same, "inconsistent_source", path, message);
}
function immutable(doc: CashEvidenceDocument): void {check(compare(doc.createTime, doc.updateTime) === 0, "overwritten_evidence", doc.path, "Immutable cash/settlement evidence was overwritten.");}
function actor(data: DocumentData, prefix: string, basis: string): ActorEvidence {
  return {uid: text(data[`${prefix}Uid`]), name: text(data[`${prefix}Name`]), role: text(data[`${prefix}Role`]), basis};
}
const notApplicable = (): ActorEvidence => ({uid: null, name: null, role: null, basis: "not_applicable"});

/** Pure exact reconstruction of a COMPLETE supplied bounded company inventory.
 * Stored receivable allocations are evidence; no cash-to-settlement allocation
 * is generated. Unknown origin always suppresses certified financial totals. */
export function analyzeSettlementSourceEvidence(input: {
  companyId: string; salesRepId: string; cutoff: Time; settlementId: string | null; currency: string;
  documents: CashEvidenceDocument[]; balances: CashEvidenceDocument[]; legacyCurrencyBound: boolean;
  initialIssues?: BreakdownIssue[]; validationProfile?: "paged_v1";
}) {
  const {companyId, salesRepId, cutoff, settlementId, currency} = input, c = `companies/${companyId}`;
  const maximumReferences = input.validationProfile === "paged_v1" ? 2048 : 32;
  const encode = input.validationProfile === "paged_v1" ? canonicalSettlementInventoryEvidence : canonical;
  const referenceCache = new WeakMap<object, string[]>();
  const ids = (value: unknown, path: string) => {
    if (Array.isArray(value) && referenceCache.has(value)) return referenceCache.get(value)!;
    const result = referenceIds(value, path, maximumReferences);
    if (Array.isArray(value)) referenceCache.set(value, result);return result;
  };
  const equal = (actual: unknown, expected: unknown, path: string, message: string) => evidenceEqual(actual, expected, path, message, encode);
  const issues: BreakdownIssue[] = [...input.initialIssues ?? []], rows: CashEvidenceRow[] = [];
  const documents = new Map(input.documents.map(d => [d.path, d]));
  const movements = input.documents.filter(d => d.path.startsWith(`${c}/cash_movements/`));
  const byId = new Map(movements.map(d => [d.id, d]));
  const normalized = new Map<string, CashEvidenceRow>();
  const inspect = (path: string, fn: () => void) => {
    try {fn();} catch (error) {
      if (!(error instanceof EvidenceProblem)) throw error;
      issues.push({code: error.code, path: error.path || path, message: error.message});
    }
  };
  const source = (collection: string, value: unknown): CashEvidenceDocument => {
    check(CASH_SOURCE_COLLECTIONS.includes(collection as typeof CASH_SOURCE_COLLECTIONS[number]), "unsupported_source", c, "Unsupported cash source collection.");
    const path = `${c}/${collection}/${identifier(value, c)}`, doc = documents.get(path);
    check(doc !== undefined, "missing_reference", path, "Referenced source document is missing.");
    check(doc.data.companyId === companyId && doc.data.id === doc.id, "source_identity", path, "Source path/company identity is inconsistent.");return doc;
  };
  const expectedMovement = (value: unknown, collection: string, sourceId: string): CashEvidenceRow => {
    const movementId = identifier(value, `${c}/${collection}/${sourceId}`), row = normalized.get(movementId);
    check(row !== undefined, "missing_movement", `${c}/cash_movements/${movementId}`, "Declared cash movement is missing or malformed.");
    equal([row.source.collection, row.source.id], [collection, sourceId], row.path, "Movement/source link differs.");return row;
  };
  const sameAmount = (row: CashEvidenceRow, value: unknown, path: string) => equal(row.amountUnits, units(value, path).toString(), path, "Source and movement amount differ.");
  const reference = (row: CashEvidenceRow, doc: CashEvidenceDocument, role: string) => {
    if (row.source.path === doc.path || row.referencedDocuments.some(d => d.path === doc.path)) return;
    check(row.referencedDocuments.length < maximumReferences, "reference_coverage", row.path, "Linked evidence exceeds its document-reference bound.");
    const date = doc.data.invoiceDate ?? doc.data.receiptDate ?? doc.data.returnDate ?? doc.data.settlementDate ?? doc.data.expenseDate ?? doc.data.movementDate;
    row.referencedDocuments.push({id: doc.id, path: doc.path,
      number: text(doc.data.invoiceNumber ?? doc.data.receiptNumber ?? doc.data.returnNumber ?? doc.data.settlementNumber ?? doc.data.sourceNumber),
      businessDate: date === undefined ? null : clock(date, doc.path), createTime: doc.createTime, updateTime: doc.updateTime, role, versionAfterCutoff: compare(doc.updateTime, cutoff) > 0});
  };
  const sellers = (row: CashEvidenceRow, invoice: CashEvidenceDocument) => {
    row.originalSellers.push({invoiceId: invoice.id, uid: text(invoice.data.salesRepId), name: text(invoice.data.salesRepName)});
    reference(row, invoice, "original_invoice");
  };
  const invoiceCache = new Map<string, CashEvidenceDocument>();
  const invoice = (value: unknown): CashEvidenceDocument => {
    if (typeof value === "string" && invoiceCache.has(value)) return invoiceCache.get(value)!;
    const doc = source("invoices", value);
    check(doc.data.financialPosted === true && ["confirmed", "accepted"].includes(doc.data.invoiceStatus), "unposted_source", doc.path, "Invoice is not financially posted.");
    const initial = units(doc.data.initialPaidAmount, doc.path), total = units(doc.data.grandTotal, doc.path);
    check(initial >= 0n && initial <= total, "inconsistent_source", doc.path, "Original invoice payment exceeds its valid total.");invoiceCache.set(doc.id, doc);return doc;
  };
  const allocationCache = new Map<string, {invoiceId: string; amountUnits: string}[]>();
  const allocations = (doc: CashEvidenceDocument) => {
    if (allocationCache.has(doc.path)) return allocationCache.get(doc.path)!;
    const map = doc.data.invoiceAllocations;
    check(map !== null && typeof map === "object" && !Array.isArray(map) && Object.keys(map).length <= maximumReferences,
      "reference_coverage", doc.path, "Receipt allocations are missing or exceed their evidence bound.");
    const result = Object.keys(map).sort().map(invoiceId => {
      identifier(invoiceId, doc.path);const amount = units(map[invoiceId], doc.path);
      check(amount > 0n, "inconsistent_source", doc.path, "Receivable allocations must be positive.");
      return {invoiceId, amountUnits: amount.toString()};
    });allocationCache.set(doc.path, result);return result;
  };

  // Normalize actual cash rows once, including other holders. A company cash row
  // may carry a seller's salesRepId; custody is ALWAYS the company in that case.
  const logical = new Set<string>();
  for (const doc of movements) inspect(doc.path, () => {
    const m = doc.data;immutable(doc);
    equal([m.id, m.companyId], [doc.id, companyId], doc.path, "Movement path/company identity differs.");
    check(!(m.isReversal === true || text(m.reversesMovementId) !== null) || m.movementType === "receipt_cancellation",
      "unsupported_adjustment", doc.path, "Only the existing receipt-cancellation cash reversal contract is supported.");
    check(m.cashAccount === "company_cash" || m.cashAccount === "rep_cash", "unknown_holder", doc.path, "Cash account is unavailable.");
    const holderUid = m.cashAccount === "company_cash" ? companyId : identifier(m.salesRepId, doc.path);
    const holderType = m.cashAccount === "company_cash" ? "company" : "representative";
    for (const [key, value] of Object.entries({holderUid, holderType, treasuryAccountId: cashBalanceDocumentId(m.cashAccount, m.cashAccount === "rep_cash" ? holderUid : "")}))
      if (m[key] !== undefined) equal(m[key], value, doc.path, `Conflicting ${key}.`);
    if (m.cashAccount === "rep_cash" && m.cashAccountSalesRepId !== undefined) equal(m.cashAccountSalesRepId, holderUid, doc.path, "Conflicting cash holder alias.");
    if (m.currency !== undefined) equal(m.currency, currency, doc.path, "Movement currency differs.");
    if (m.moneyScale !== undefined) equal(m.moneyScale, 3, doc.path, "Movement scale differs.");
    check(input.legacyCurrencyBound || m.currency === currency && m.moneyScale === 3, "unknown_currency", doc.path, "Legacy cash currency has no approved company-ledger binding.");
    check(m.direction === "in" || m.direction === "out", "invalid_direction", doc.path, "Cash direction is unavailable.");
    const amount = units(m.amount, doc.path), before = units(m.balanceBefore, doc.path), after = units(m.balanceAfter, doc.path);
    check(amount > 0n && before >= 0n && after >= 0n, "invalid_cash", doc.path, "Physical cash amounts must be positive/nonnegative.");
    const signed = m.direction === "in" ? amount : -amount;
    equal(sumUnits([before, signed]).toString(), after.toString(), doc.path, "Exact movement equation differs.");
    const recordedAt = clock(m.createdAt, doc.path), businessDate = clock(m.movementDate, doc.path);
    equal(clock(m.date, doc.path), businessDate, doc.path, "Movement business dates differ.");
    check(compare(recordedAt, doc.createTime) <= 0, "invalid_timestamp", doc.path, "Recorded time exceeds SDK creation witness.");
    const collection = identifier(m.sourceCollection, doc.path), sourceId = identifier(m.sourceId, doc.path);
    equal(m.referenceId, sourceId, doc.path, "Cash reference/source ID differs.");
    identifier(m.movementType, doc.path);
    const key = digest([collection, sourceId, m.movementType, m.cashAccount, holderUid, m.direction]);
    check(!logical.has(key), "duplicate_movement", doc.path, "Duplicate logical cash movement.");logical.add(key);
    const origin = source(collection, sourceId);
    check(compare(origin.createTime, doc.createTime) <= 0, "invalid_timestamp", doc.path, "Cash movement predates source creation.");
    const sourceDateField = ({invoices: "invoiceDate", receipts: "receiptDate", sales_returns: "returnDate", expenses: "expenseDate", settlements: "settlementDate"} as Record<string, string>)[collection];
    const sourcePostedAt = origin.data.postedAt ?? origin.data.financialPostedAt ?? origin.data.approvedAt;
    const row: CashEvidenceRow = {id: doc.id, path: doc.path, category: "unsupported_adjustment", verification: "blocked",
      cashAccount: m.cashAccount, holderType, holderUid, amountUnits: amount.toString(), signedUnits: signed.toString(), beforeUnits: before.toString(), afterUnits: after.toString(),
      committedAt: doc.createTime, recordedAt, businessDate,
      source: {collection, id: sourceId, path: origin.path, createTime: origin.createTime, updateTime: origin.updateTime, versionAfterCutoff: compare(origin.updateTime, cutoff) > 0,
        recordedCreatedAt: origin.data.createdAt === undefined ? null : clock(origin.data.createdAt, origin.path), recordedPostedAt: sourcePostedAt === undefined ? null : clock(sourcePostedAt, origin.path),
        businessDate: sourceDateField && origin.data[sourceDateField] !== undefined ? clock(origin.data[sourceDateField], origin.path) : null},
      sourceNumber: text(m.sourceNumber), movementCreator: actor(m, "createdBy", "movement.createdBy"),
      sourceCreator: actor(origin.data, "createdBy", "source.createdBy"), collector: notApplicable(), postingActor: actor(m, "createdBy", "movement.createdBy"),
      recordedProvenance: {sellerId: text(m.sellerId), sellerName: text(m.sellerName), collector: {uid: text(m.collectorUid), name: text(m.collectorName), role: null, basis: "movement.collector"},
        postedBy: actor(m, "postedBy", "movement.postedBy"), sourceCreatedBy: actor(m, "sourceCreatedBy", "movement.sourceCreatedBy")},
      recordedSalesRepId: text(m.salesRepId), originalSellers: [], receivableAllocations: [], collectionMovementIds: [], reversesMovementId: text(m.reversesMovementId),
      counterpartMovementId: text(m.counterpartMovementId), unallocatedReceiptUnits: null, referencedDocuments: []};
    check(row.movementCreator.uid !== null && row.sourceCreator.uid !== null, "missing_identity", doc.path, "Recorded creator identity is missing.");
    identifier(row.movementCreator.uid, doc.path);identifier(row.sourceCreator.uid, doc.path);
    normalized.set(row.id, row);rows.push(row);
  });

  // Source-specific validation never treats source totals or invoice allocations
  // as another cash inflow. They annotate the SAME authoritative movement.
  for (const row of rows) inspect(row.path, () => {
    const doc = byId.get(row.id)!, m = doc.data, origin = source(row.source.collection, row.source.id), s = origin.data;
    const direction = (expected: "in" | "out") => equal(m.direction, expected, doc.path, "Source cash direction differs.");
    if (s.currency !== undefined) equal(s.currency, currency, origin.path, "Source currency differs.");
    if (s.moneyScale !== undefined) equal(s.moneyScale, 3, origin.path, "Source money scale differs.");
    const dateField = ({invoices: "invoiceDate", receipts: m.movementType === "receipt_cancellation" ? "cancelledAt" : "receiptDate", sales_returns: "returnDate", expenses: "expenseDate", settlements: "settlementDate"} as Record<string, string>)[row.source.collection];
    if (dateField) equal(clock(s[dateField], origin.path), row.businessDate, doc.path, "Source/movement business date differs.");
    const numberField = ({invoices: "invoiceNumber", receipts: "receiptNumber", sales_returns: "returnNumber", settlements: "settlementNumber"} as Record<string, string>)[row.source.collection];
    if (numberField) equal([m.sourceNumber, m.referenceNumber], [s[numberField], s[numberField]], doc.path, "Source display references differ.");
    switch (m.movementType) {
    case "opening_balance":
      equal([row.source.collection, row.source.id, m.type, m.immutable, m.createdByRole, row.beforeUnits],
        ["cash_movements", row.id, "opening_balance", true, "admin", "0"], doc.path, "Opening lacks immutable zero-origin declaration.");
      direction("in");row.category = "opening";break;
    case "invoice_payment": {
      const inv = invoice(row.source.id);equal(row.source.collection, "invoices", doc.path, "Invoice source collection differs.");
      direction("in");sameAmount(row, s.initialPaidAmount, origin.path);
      check(units(s.initialPaidAmount, origin.path) <= units(s.grandTotal, origin.path) && ["cash", "partial"].includes(s.paymentType),
        "inconsistent_source", origin.path, "Initial cash exceeds invoice total or its payment type differs.");
      equal(m.paymentType, s.paymentType, doc.path, "Invoice movement payment type differs.");
      equal(ids(s.cashMovementIds, origin.path), [row.id], origin.path, "Invoice cash IDs differ.");
      equal(row.id, `${inv.id}_cash`, doc.path, "Invoice cash ID differs.");
      equal(m.type, s.paymentType === "partial" ? "invoice_partial" : "invoice_cash", doc.path, "Invoice collection type differs.");
      equal(row.cashAccount, s.initialCashAccount, origin.path, "Initial invoice collection account differs.");
      equal(row.cashAccount, s.createdByRole === "sales_rep" ? "rep_cash" : "company_cash", origin.path, "Invoice creator/custody evidence differs.");
      if (row.cashAccount === "rep_cash") equal(row.holderUid, s.salesRepId, origin.path, "Invoice holder differs.");
      equal(m.customerId, s.customerId, doc.path, "Invoice customer differs.");sellers(row, inv);
      equal(m.createdByUid, s.createdByUid, doc.path, "Invoice source creator snapshot differs.");
      row.postingActor = actor(s, "financialPostedBy", "invoice.financialPostedBy");
      row.collector = m.collectorUid ? row.recordedProvenance.collector : {uid: null, name: null, role: null, basis: "physical_collector_not_recorded"};
      row.category = "invoice_collection";break;
    }
    case "receipt":
    case "receipt_cancellation": {
      equal(row.source.collection, "receipts", doc.path, "Receipt source collection differs.");
      check(s.paymentMethod === "cash" && (s.status === undefined || ["posted", "cancelled"].includes(s.status)), "unposted_source", origin.path, "Receipt is not a supported cash receipt.");
      sameAmount(row, s.amount, origin.path);equal(m.customerId, s.customerId, doc.path, "Receipt customer differs.");
      const originalIds = ids(s.cashMovementIds, origin.path);check(originalIds.length === 1, "reference_coverage", origin.path, "Exactly one receipt collection movement is required.");
      const incoming = expectedMovement(originalIds[0], "receipts", origin.id);
      if (incoming.id !== row.id) reference(row, byId.get(incoming.id)!, "reversed_cash_movement");
      equal([incoming.cashAccount, incoming.holderUid], [row.cashAccount, row.holderUid], doc.path, "Receipt reversal paying holder differs.");
      equal(incoming.amountUnits, row.amountUnits, doc.path, "Receipt reversal amount differs.");
      if (row.cashAccount === "rep_cash") equal(row.holderUid, s.createdByUid, origin.path, "Receipt collector differs from cash holder.");
      else equal(s.createdByRole, "admin", origin.path, "Company receipt collector role differs.");
      row.collector = actor(s, "createdBy", "receipt.createdBy");row.receivableAllocations = allocations(origin);
      if (m.collectorUid) equal(m.collectorUid, s.createdByUid, origin.path, "Explicit receipt collector differs.");
      const allocated = sumUnits(row.receivableAllocations.map(a => BigInt(a.amountUnits)));
      check(allocated <= BigInt(row.amountUnits), "inconsistent_source", origin.path, "Receipt allocations exceed its single cash amount.");
      row.unallocatedReceiptUnits = (BigInt(row.amountUnits) - allocated).toString();
      check(Array.isArray(s.invoiceAllocationDetails) && s.invoiceAllocationDetails.length === row.receivableAllocations.length,
        "reference_coverage", origin.path, "Receipt allocation details are missing or duplicated.");
      const details = s.invoiceAllocationDetails.map((a: DocumentData) => ({invoiceId: identifier(a.invoiceId, origin.path), amountUnits: units(a.amount, origin.path).toString()})).sort((a: {invoiceId: string}, b: {invoiceId: string}) => a.invoiceId.localeCompare(b.invoiceId));
      equal(details, row.receivableAllocations, origin.path, "Receipt allocation representations differ.");
      for (const allocation of row.receivableAllocations) {
        const inv = invoice(allocation.invoiceId);equal(inv.data.customerId, s.customerId, inv.path, "Receipt allocation crosses customers.");
        check(BigInt(allocation.amountUnits) <= units(inv.data.grandTotal, inv.path), "inconsistent_source", inv.path, "Receipt allocation exceeds original invoice total.");
        const invoiceReceiptIds = ids(s.status === "cancelled" ? inv.data.cancelledReceiptIds : inv.data.receiptIds, inv.path);
        check(invoiceReceiptIds.includes(origin.id), "missing_reference", inv.path, "Reciprocal invoice/receipt reference is missing.");sellers(row, inv);
      }
      if (m.movementType === "receipt") {
        direction("in");equal(originalIds, [row.id], origin.path, "Receipt original movement differs.");
        equal(m.createdByUid, s.createdByUid, doc.path, "Receipt original collector/creator differs.");
        equal(m.type, "receipt_cash", doc.path, "Receipt movement type differs.");
        if (s.status === "cancelled") check(ids(s.cancellationCashMovementIds, origin.path).length === 1, "missing_reference", origin.path, "Receipt cancellation cash evidence is missing.");
        row.category = "receipt_collection";
      } else {
        direction("out");equal([s.status, s.cancellationVersion, m.type], ["cancelled", 1, "receipt_cancellation"], origin.path, "Receipt cancellation evidence differs.");
        equal(ids(s.cancellationCashMovementIds, origin.path), [row.id], origin.path, "Cancellation movement reference differs.");
        equal(m.reversesMovementId, incoming.id, doc.path, "Cancellation original movement differs.");
        equal(m.createdByUid, s.cancelledByUid, doc.path, "Cancellation posting actor differs.");
        check(compare(incoming.committedAt, row.committedAt) < 0, "invalid_timestamp", doc.path, "Cancellation precedes original collection.");
        row.postingActor = actor(s, "cancelledBy", "receipt.cancelledBy");row.category = "receipt_cancellation";
      }
      break;
    }
    case "sales_return": {
      equal([row.source.collection, s.status, s.financialPosted, s.refundType, m.type],
        ["sales_returns", "confirmed", true, "cash_refund", "sales_return_cash_refund"], origin.path, "Cash refund source/status differs.");
      direction("out");sameAmount(row, s.cashRefundAmount, origin.path);equal(ids(s.cashMovementIds, origin.path), [row.id], origin.path, "Refund movement reference differs.");
      check(BigInt(row.amountUnits) <= units(s.grandTotal, origin.path), "inconsistent_source", origin.path, "Cash refund exceeds the return value.");
      const inv = invoice(s.originalInvoiceId);equal(s.customerId, inv.data.customerId, origin.path, "Return original customer differs.");
      check(ids(inv.data.returnInvoiceIds, inv.path).includes(s.id), "missing_reference", inv.path, "Invoice/return reciprocal reference is missing.");
      equal(m.customerId, s.customerId, doc.path, "Refund customer differs.");sellers(row, inv);
      row.collectionMovementIds = ids(m.originalCollectionSourceIds, doc.path);
      check(row.collectionMovementIds.length > 0, "missing_reference", doc.path, "Refund paying collection evidence is missing.");
      for (const ref of row.collectionMovementIds) {
        const incoming = normalized.get(ref);check(incoming !== undefined, "missing_reference", doc.path, "Original refund collection is missing.");
        equal([incoming.cashAccount, incoming.holderUid], [row.cashAccount, row.holderUid], doc.path, "Refund spans different paying cash holders.");
        check(BigInt(incoming.signedUnits) > 0n && compare(incoming.committedAt, row.committedAt) < 0,
          "inconsistent_source", doc.path, "Refund collection is not an earlier cash inflow.");
        const originalSource = source(incoming.source.collection, incoming.source.id);
        reference(row, byId.get(incoming.id)!, "original_collection_movement");reference(row, originalSource, "original_collection_source");
        check(incoming.source.collection === "invoices" && incoming.source.id === inv.id ||
          incoming.source.collection === "receipts" && allocations(originalSource).some(a => a.invoiceId === inv.id),
        "inconsistent_source", doc.path, "Refund collection does not reference the original invoice.");
      }
      row.collector = {uid: row.cashAccount === "rep_cash" ? row.holderUid : null, name: null, role: null, basis: "verified_original_collection_holder"};
      row.category = "cash_refund";break;
    }
    case "expense":
      equal(row.source.collection, "expenses", doc.path, "Expense source collection differs.");
      equal(m.type, "expense_cash", doc.path, "Expense movement type differs.");
      check(["approved", "posted"].includes(s.status) && s.paymentMethod === "cash", "unposted_source", origin.path, "Expense is not approved/posted cash funding.");
      direction("out");sameAmount(row, s.amount, origin.path);equal(s.cashMovementId, row.id, origin.path, "Expense cash reference differs.");
      equal(s.fundingSource, row.cashAccount === "rep_cash" ? "rep_collected_cash" : "company_cash", origin.path, "Expense paying account differs.");
      if (row.cashAccount === "rep_cash") equal(s.salesRepId, row.holderUid, origin.path, "Expense representative holder differs.");
      equal(m.createdByUid, s.approvedByUid, doc.path, "Expense approving actor differs.");
      row.postingActor = actor(s, "approvedBy", "expense.approvedBy");row.category = "cash_expense";break;
    case "settlement_to_admin": {
      immutable(origin);equal([row.source.collection, s.status, m.type], ["settlements", "posted", "settlement_to_admin"], origin.path, "Settlement source/status differs.");
      sameAmount(row, s.amount, origin.path);
      const out = expectedMovement(s.repMovementId, "settlements", origin.id), incoming = expectedMovement(s.companyMovementId, "settlements", origin.id);
      equal([out.cashAccount, out.holderUid, incoming.cashAccount, incoming.holderUid], ["rep_cash", s.salesRepId, "company_cash", companyId], origin.path, "Settlement custody pair differs.");
      equal([out.signedUnits, incoming.signedUnits], [(-units(s.amount, origin.path)).toString(), units(s.amount, origin.path).toString()], origin.path, "Settlement pair does not conserve cash.");
      equal([out.committedAt, incoming.committedAt], [origin.createTime, origin.createTime], origin.path, "Settlement effects are not atomic.");
      equal(m.counterpartMovementId, row.id === out.id ? incoming.id : out.id, doc.path, "Settlement reciprocal movement differs.");
      equal(row.id, row.cashAccount === "rep_cash" ? out.id : incoming.id, doc.path, "Unexpected settlement leg.");
      equal([s.sourceCashAccount, s.sourceCashAccountId, s.destinationCashAccount, s.destinationCashAccountId],
        ["rep_cash", `rep_${s.salesRepId}`, "company_cash", "company_cash"], origin.path, "Settlement source/destination differs.");
      equal(m.accounting ?? null, s.accounting ?? null, doc.path, "Settlement accounting binding differs.");
      equal(s.createdByRole, "admin", origin.path, "Settlement posting authority is missing.");
      equal([m.createdByUid, m.postedByUid, m.sourceCreatedByUid], [s.createdByUid, s.postedByUid, s.sourceCreatedByUid], doc.path, "Settlement actor bindings differ.");
      row.postingActor = actor(s, "postedBy", "settlement.postedBy");
      row.category = "settlement";break;
    }
    default: check(false, "unsupported_adjustment", doc.path, "No approved source contract exists for this cash adjustment.");
    }
    check(row.postingActor.uid !== null, "missing_identity", doc.path, "Posting actor is not recorded.");identifier(row.postingActor.uid, doc.path);
    row.verification = "verified";
  });

  // Enumerate declared effects too: movement-only scans cannot discover an
  // approved source whose cash leg has disappeared (or was never written).
  for (const doc of input.documents.filter(d => !d.path.startsWith(`${c}/cash_movements/`))) inspect(doc.path, () => {
    const s = doc.data, collection = doc.path.split("/").at(-2)!;
    equal([s.id, s.companyId], [doc.id, companyId], doc.path, "Source scope/identity differs.");
    const declared = (value: unknown, kind: string) => {for (const ref of ids(value, doc.path)) expectedMovement(ref, kind, doc.id);};
    if (collection === "invoices" && s.financialPosted === true) {
      const paid = units(s.initialPaidAmount, doc.path), refs = ids(s.cashMovementIds, doc.path);
      check(paid >= 0n, "inconsistent_source", doc.path, "Initial invoice payment cannot be negative.");
      equal(refs.length, paid > 0n ? 1 : 0, doc.path, "Initial invoice cash coverage differs.");declared(refs, collection);
      for (const field of ["receiptIds", "cancelledReceiptIds"]) if (s[field] !== undefined) for (const receiptId of ids(s[field], doc.path)) {
        const receipt = source("receipts", receiptId), a = allocations(receipt).find(a => a.invoiceId === doc.id);
        check(a !== undefined && receipt.data.customerId === s.customerId, "missing_reference", doc.path, "Recorded invoice receipt has no reciprocal allocation/customer evidence.");
        check(field === "cancelledReceiptIds" ? receipt.data.status === "cancelled" : receipt.data.status !== "cancelled",
          "inconsistent_source", doc.path, "Invoice active/cancelled receipt history differs.");
      }
      if (s.returnInvoiceIds !== undefined) for (const returnId of ids(s.returnInvoiceIds, doc.path)) {
        const returned = source("sales_returns", returnId);
        check(returned.data.originalInvoiceId === doc.id && returned.data.status === "confirmed", "missing_reference", doc.path, "Recorded invoice return has no reciprocal confirmed source.");
      }
    } else if (collection === "receipts") {
      const refs = ids(s.cashMovementIds, doc.path);equal(refs.length, s.paymentMethod === "cash" ? 1 : 0, doc.path, "Receipt cash coverage differs.");declared(refs, collection);
      if (s.status === "cancelled") {const refs = ids(s.cancellationCashMovementIds, doc.path);equal(refs.length, s.paymentMethod === "cash" ? 1 : 0, doc.path, "Cancellation cash coverage differs.");declared(refs, collection);}
    } else if (collection === "sales_returns" && s.status === "confirmed") {
      const amount = units(s.cashRefundAmount, doc.path), refs = ids(s.cashMovementIds, doc.path);
      check(amount >= 0n, "inconsistent_source", doc.path, "Cash refund amount cannot be negative.");
      equal(refs.length, amount > 0n ? 1 : 0, doc.path, "Return cash coverage differs.");
      if (s.refundType === "credit_customer_balance") equal(amount.toString(), "0", doc.path, "Customer-credit return cannot consume cash.");declared(refs, collection);
    } else if (collection === "expenses") {
      const cash = ["approved", "posted"].includes(s.status) && s.fundingSource !== "personal_cash";
      if (cash) expectedMovement(s.cashMovementId, collection, doc.id);
      else check(!s.cashMovementId, "inconsistent_source", doc.path, "Unpaid/personal expense claims a cash movement.");
    } else if (collection === "settlements" && s.status === "posted") {
      declared([s.repMovementId, s.companyMovementId], collection);
    }
  });

  // Validate cumulative invoice refund caps using ONLY persisted receivable
  // allocations, never by allocating fungible settlement cash to invoices.
  const collectionsByInvoice = new Map<string, CashEvidenceRow[]>(), refundsByInvoice = new Map<string, CashEvidenceRow[]>();
  const allocationUnitsByMovement = new Map<string, Map<string, bigint>>();
  const reversalsByOriginal = new Map<string, CashEvidenceRow[]>(), representedSources = new Set(rows.map(r => r.source.path));
  const append = (map: Map<string, CashEvidenceRow[]>, key: string, row: CashEvidenceRow) => {
    const values = map.get(key) ?? [];values.push(row);map.set(key, values);
  };
  for (const row of rows) {
    if (row.category === "invoice_collection") append(collectionsByInvoice, row.source.id, row);
    if (row.category === "receipt_collection") {
      allocationUnitsByMovement.set(row.id, new Map(row.receivableAllocations.map(a => [a.invoiceId, BigInt(a.amountUnits)])));
      for (const a of row.receivableAllocations) append(collectionsByInvoice, a.invoiceId, row);
    }
    if (row.category === "receipt_cancellation" && row.reversesMovementId) append(reversalsByOriginal, row.reversesMovementId, row);
    if (row.category === "cash_refund") append(refundsByInvoice, source("sales_returns", row.source.id).data.originalInvoiceId, row);
  }
  for (const row of rows.filter(r => r.category === "cash_refund")) inspect(row.path, () => {
    const invId = source("sales_returns", row.source.id).data.originalInvoiceId;
    const eligible = (collectionsByInvoice.get(invId) ?? []).filter(r => compare(r.committedAt, row.committedAt) < 0 &&
      !(reversalsByOriginal.get(r.id) ?? []).some(cancel => compare(cancel.committedAt, row.committedAt) < 0));
    equal([...row.collectionMovementIds].sort(), eligible.map(r => r.id).sort(), row.path, "Refund collection coverage is incomplete or mixed.");
    check(eligible.every(r => r.cashAccount === row.cashAccount && r.holderUid === row.holderUid), "mixed_refund_holders", row.path, "Refund spans multiple original collection holders.");
    const collected = sumUnits(eligible.map(r => r.category === "invoice_collection" ? BigInt(r.amountUnits) : allocationUnitsByMovement.get(r.id)!.get(invId)!));
    const refunded = sumUnits((refundsByInvoice.get(invId) ?? []).filter(r => compare(r.committedAt, row.committedAt) <= 0).map(r => BigInt(r.amountUnits)));
    check(refunded <= collected, "refund_exceeds_collections", row.path, "Cumulative refunds exceed verified invoice cash collections.");
  });

  const selected = rows.filter(r => r.cashAccount === "rep_cash" && r.holderUid === salesRepId)
    .sort((a, b) => compare(a.committedAt, b.committedAt) || a.id.localeCompare(b.id));
  const selectedIds = new Set(selected.map(r => r.id));
  let opening: {state: "verified_recorded_opening" | "unknown"; amountUnits: string | null; movementId: string | null} = {state: "unknown", amountUnits: null, movementId: null};
  if (selected[0]?.category === "opening" && selected[0].verification === "verified" && compare(selected[0].committedAt, cutoff) <= 0) opening = {state: "verified_recorded_opening", amountUnits: selected[0].amountUnits, movementId: selected[0].id};
  else issues.push({code: "unknown_opening", path: `${c}/cash_balances/rep_${salesRepId}`, message: "No verified recorded opening; an observed zero/balance is not an opening attestation."});
  for (const [index, row] of selected.entries()) inspect(row.path, () => {
    if (index > 0) {
      check(row.category !== "opening", "multiple_openings", row.path, "Another opening cannot restart an existing cash history.");
      check(compare(selected[index - 1].committedAt, row.committedAt) < 0, "ambiguous_commit_order", row.path, "Multiple movements share an account commit; no arbitrary ordering is allowed.");
      check(row.beforeUnits === selected[index - 1].afterUnits, "incomplete_movement_coverage", row.path, "Committed account cash chain has a gap.");
    }
  });
  const relevantAccounts = settlementId ? ["rep_cash", "company_cash"] : ["rep_cash"];
  for (const account of relevantAccounts) inspect(`${c}/cash_balances`, () => {
    const accountId = cashBalanceDocumentId(account as "rep_cash" | "company_cash", account === "rep_cash" ? salesRepId : "");
    const balance = input.balances.find(b => b.id === accountId);
    check(balance !== undefined, "missing_balance", `${c}/cash_balances/${accountId}`, "Current cash position is missing.");
    const data = balance.data, holder = account === "rep_cash" ? salesRepId : companyId;
    equal([data.id, data.companyId, data.cashAccount, data.salesRepId], [accountId, companyId, account, account === "rep_cash" ? salesRepId : ""], balance.path, "Cash position identity differs.");
    for (const [key, value] of Object.entries({holderUid: holder, holderType: account === "rep_cash" ? "representative" : "company", treasuryAccountId: accountId, currency, moneyScale: 3}))
      if (data[key] !== undefined) equal(data[key], value, balance.path, `Cash position ${key} differs.`);
    check(input.legacyCurrencyBound || data.currency === currency && data.moneyScale === 3, "unknown_currency", balance.path, "Cash balance currency is not evidenced.");
    const heads = rows.filter(r => r.cashAccount === account && r.holderUid === holder).sort((a, b) => compare(a.committedAt, b.committedAt));
    const last = heads.at(-1);check(last !== undefined && last.id === data.lastMovementId, "missing_cash_head", balance.path, "Cash head is not the latest scanned account movement.");
    equal(units(data.amount, balance.path).toString(), last.afterUnits, balance.path, "Current balance differs from cash head.");
    equal(balance.updateTime, last.committedAt, balance.path, "Cash position/head SDK versions differ.");
    equal(clock(data.updatedAt, balance.path), last.recordedAt, balance.path, "Cash position/head recorded timestamps differ.");
  });
  const current = settlementId ? selected.find(r => r.source.collection === "settlements" && r.source.id === settlementId) : undefined;
  if (settlementId) inspect(`${c}/settlements/${settlementId}`, () => {
    check(current !== undefined && current.category === "settlement" && compare(current.committedAt, cutoff) === 0,
      "invalid_settlement_cutoff", `${c}/settlements/${settlementId}`, "Selected settlement has no matching immutable representative OUT at its SDK commit cutoff.");
  });
  const prefix = selected.filter(r => settlementId ? compare(r.committedAt, cutoff) < 0 : compare(r.committedAt, cutoff) <= 0);
  const previous = prefix.filter(r => r.category === "settlement").at(-1);
  const sinceCarry = prefix.filter(r => r.category !== "opening" && (!previous || compare(r.committedAt, previous.committedAt) > 0));
  const carryUnits = previous?.afterUnits ?? opening.amountUnits;
  let totals: SettlementCashTotals | null = null;
  if (issues.length === 0 && opening.amountUnits !== null && carryUnits !== null) inspect(c, () => {
    const available = sumUnits(prefix.map(r => BigInt(r.signedUnits)));
    equal(sumUnits([BigInt(carryUnits), ...sinceCarry.map(r => BigInt(r.signedUnits))]).toString(), available.toString(), c, "Carry and subsequent activity do not reconcile.");
    const transferred = current ? BigInt(current.amountUnits) : 0n, remaining = sumUnits([available, -transferred]);
    if (current) equal([current.beforeUnits, current.afterUnits], [available.toString(), remaining.toString()], current.path, "Selected settlement before/after differs from reconstructed cash.");
    totals = {openingUnits: opening.amountUnits!, carryUnits: carryUnits!, activitySinceCarryUnits: sumUnits(sinceCarry.map(r => BigInt(r.signedUnits))).toString(),
      cashAvailableBeforeUnits: available.toString(), transferredUnits: transferred.toString(), remainingUnits: remaining.toString(), currentBalanceUnits: selected.at(-1)!.afterUnits};
  });
  if (issues.length) totals = null;
  const categoryTotals = Object.fromEntries([...new Set(prefix.map(r => r.category))].sort().map(category => [category, sumUnits(prefix.filter(r => r.category === category).map(r => BigInt(r.signedUnits))).toString()]));
  const positiveOrUnknown = (value: unknown) => {try {return money(value) > 0n;} catch {return true;}};
  const expectsCash = (collection: string, s: DocumentData) => collection === "receipts" ? s.paymentMethod === "cash" : collection === "settlements" ? s.status === "posted" :
    collection === "expenses" ? ["approved", "posted"].includes(s.status) && s.fundingSource !== "personal_cash" :
      collection === "invoices" ? s.financialPosted === true && positiveOrUnknown(s.initialPaidAmount) : s.status === "confirmed" && positiveOrUnknown(s.cashRefundAmount);
  const unrepresented = (collection: string) => input.documents.filter(d => d.path.startsWith(`${c}/${collection}/`) && !representedSources.has(d.path));
  const nonCashSources = Object.fromEntries(CASH_SOURCE_COLLECTIONS.filter(collection => collection !== "cash_movements").map(collection => [collection,
    unrepresented(collection).filter(d => !expectsCash(collection, d.data)).map(d => ({id: d.id, path: d.path,
      status: text(d.data.status ?? d.data.invoiceStatus), reason: collection === "expenses" ? d.data.fundingSource === "personal_cash" ? "personal_payable_no_cash" : "unpaid_expense" :
        collection === "sales_returns" ? "customer_credit_or_debt_reduction" : "no_recorded_cash_effect", createTime: d.createTime, updateTime: d.updateTime}))]));
  const unresolvedSources = Object.fromEntries(CASH_SOURCE_COLLECTIONS.filter(collection => collection !== "cash_movements").map(collection => [collection,
    unrepresented(collection).filter(d => expectsCash(collection, d.data)).map(d => ({id: d.id, path: d.path, reason: "cash_evidence_missing_or_malformed"}))]));
  return {status: issues.length ? "blocked" as const : "verified_cash_reconstruction" as const,
    opening, carry: {state: (totals ? "verified" : "unverifiable") as "verified" | "unverifiable",
      amountUnits: (totals ? carryUnits : null) as string | null, previousSettlementId: previous?.source.id ?? null},
    // Preserve the nullable public type: TS cannot see assignments made inside
    // the synchronous inspect() callback used for fail-closed arithmetic.
    totals: totals as SettlementCashTotals | null, observedCategoryNetUnits: categoryTotals, movements: selected,
    excludedMovements: rows.filter(r => !selectedIds.has(r.id)).map(r => ({...r, exclusionReason: "different_cash_holder" as const})),
    committedOrder: selected.map(r => r.id), businessDatePresentationOrder: [...selected].sort((a, b) => compare(a.businessDate, b.businessDate) || compare(a.committedAt, b.committedAt) || a.id.localeCompare(b.id)).map(r => r.id),
    cutoffMovementIds: selected.filter(r => compare(r.committedAt, cutoff) <= 0).map(r => r.id), nonCashSources, unresolvedSources,
    issueCount: issues.length, issues: issues.slice(0, 64), issuesTruncated: issues.length > 64,
    allocation: {status: "not_implemented" as const, settlementSourceAllocations: null, receivableAllocationsAreSettlementAllocations: false as const},
    coverage: {scope: "representative_cash_chain_and_settlement_pair" as const, inventory: "complete_within_bound" as const, historicalSourceContents: "current_source_versions_only" as const,
      privilegedHistoryAuthenticity: "not_certified" as const, unknownOpeningAssumedZero: false as const}};
}
