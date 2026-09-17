import {createHash} from "node:crypto";
import {
  DocumentData,
  FieldPath,
  FieldValue,
  Firestore,
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
import {FINANCIAL_LEDGER_SCHEMA_VERSION} from "./financial_ledger";
import {ledgerSummaryShard} from "./financial_ledger_reporting";

export const ACCOUNT_ACTIVITY_PROJECTION_VERSION = 1;
export const ACCOUNT_ACTIVITY_STATE_COLLECTION =
  "financial_ledger_account_activity_states";
export const ACCOUNT_ACTIVITY_SCOPE_COLLECTION =
  "financial_ledger_account_activity_scopes";
export const ACCOUNT_ACTIVITY_METADATA_COLLECTION =
  "financial_ledger_account_activity_metadata";

const MAX_ACCOUNT_KEYS = 200;
const MAX_ACCOUNT_KEY_BYTES = 512;
const MAX_SALES_REP_ID_BYTES = 128;

export interface AccountActivity {
  accountKey: string;
  accountType: string;
  accountName: string;
  debit: number;
  credit: number;
  netChange: number;
}

export interface AccountActivityProjection {
  fingerprint: string;
  occurredAt: Timestamp;
  dayKey: string;
  monthKey: string;
  shard: string;
  postingId: string;
  salesRepId: string;
  activities: AccountActivity[];
}

interface AccountActivityState extends AccountActivityProjection {}

interface AccountDelta {
  account: AccountActivity;
  entryCount: number;
  debit: number;
  credit: number;
  netChange: number;
}

interface AccountOpening {
  accountKey: string;
  accountType: string;
  accountName: string;
  debit: number;
  credit: number;
  balance: number;
  lastActivityAt?: number;
}

export const projectFinancialLedgerAccountActivity = onDocumentWritten(
  {
    document: "companies/{companyId}/financial_ledger_entries/{entryId}",
    region: REGION,
    retry: true,
  },
  async (event) => {
    await reconcileFinancialLedgerAccountActivity(
      getFirestore(),
      String(event.params.companyId),
      String(event.params.entryId),
    );
  },
);

export const getFinancialLedgerOpeningBalances = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    const uid = requireCallableUid(request, "getFinancialLedgerOpeningBalances");
    const input = record(request.data);
    const companyId = requiredDocumentId(input.companyId, "companyId");
    const firestore = getFirestore();
    await requireLedgerAdmin(firestore, uid, companyId);
    const metadata = await firestore.doc(businessPath(
      companyId,
      ACCOUNT_ACTIVITY_METADATA_COLLECTION,
      "current",
    )).get();
    if (
      !metadata.exists ||
      metadata.get("status") !== "ready" ||
      metadata.get("projectionVersion") !== ACCOUNT_ACTIVITY_PROJECTION_VERSION
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Financial ledger account activity projection is not ready.",
      );
    }
    const fromInclusive = timestampFrom(input.fromInclusive, "fromInclusive");
    const salesRepId = scalarString(
      input.salesRepId,
      "salesRepId",
      MAX_SALES_REP_ID_BYTES,
    );
    const accountKeys = parseAccountKeys(input.accountKeys);
    const scope = salesRepId ? representativeScopeId(salesRepId) : "all";
    const openings = await loadAccountOpenings(
      firestore,
      companyId,
      scope,
      accountKeys,
      fromInclusive,
    );
    return {
      projectionVersion: ACCOUNT_ACTIVITY_PROJECTION_VERSION,
      fromInclusive: fromInclusive.toMillis(),
      scope,
      openings,
    };
  },
);

export const getCashOpeningBalance = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    const uid = requireCallableUid(request, "getCashOpeningBalance");
    const input = record(request.data);
    const companyId = requiredDocumentId(input.companyId, "companyId");
    const firestore = getFirestore();
    const user = await firestore.runTransaction((transaction) =>
      requireTrustedUser(transaction, firestore, uid, companyId));
    const metadata = await firestore.doc(businessPath(
      companyId,
      ACCOUNT_ACTIVITY_METADATA_COLLECTION,
      "current",
    )).get();
    if (
      !metadata.exists ||
      metadata.get("status") !== "ready" ||
      metadata.get("projectionVersion") !== ACCOUNT_ACTIVITY_PROJECTION_VERSION
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Financial ledger account activity projection is not ready.",
      );
    }
    const fromInclusive = timestampFrom(input.fromInclusive, "fromInclusive");
    let accountKeys: string[];
    let repNames = new Map<string, string>();
    if (user.role === "admin") {
      const reps = await firestore.collection("users")
        .where("companyId", "==", companyId)
        .where("role", "==", "sales_rep")
        .get();
      repNames = new Map(reps.docs.map((document) => [
        document.id,
        optionalString(document.data().name),
      ]));
      accountKeys = [
        "company_cash",
        ...reps.docs.map((document) => `rep_cash:${document.id}`),
      ];
    } else {
      accountKeys = [`rep_cash:${user.uid}`];
      repNames.set(user.uid, user.name);
    }
    const openings = await loadAccountOpenings(
      firestore,
      companyId,
      user.role === "admin" ? "all" : representativeScopeId(user.uid),
      accountKeys,
      fromInclusive,
    );
    const companyOpening = openings.find((opening) =>
      opening.accountKey === "company_cash")?.balance ?? 0;
    const repOpenings = openings.filter((opening) =>
      opening.accountKey.startsWith("rep_cash:"))
      .map((opening) => {
        const salesRepId = opening.accountKey.slice("rep_cash:".length);
        return {
          salesRepId,
          salesRepName: repNames.get(salesRepId) ?? "",
          amount: opening.balance,
        };
      });
    const repOpening = roundMoney(repOpenings.reduce(
      (sum, opening) => sum + opening.amount,
      0,
    ));
    return {
      projectionVersion: ACCOUNT_ACTIVITY_PROJECTION_VERSION,
      openingBalance: user.role === "admin" ? companyOpening : repOpening,
      companyCashOpening: companyOpening,
      repCashOpening: repOpening,
      repCashOpeningBySalesRep: repOpenings,
    };
  },
);

export const getReceivableBalances = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    const uid = requireCallableUid(request, "getReceivableBalances");
    const input = record(request.data);
    const companyId = requiredDocumentId(input.companyId, "companyId");
    const firestore = getFirestore();
    const user = await firestore.runTransaction((transaction) =>
      requireTrustedUser(transaction, firestore, uid, companyId));
    await requireAccountActivityProjection(firestore, companyId);
    const atExclusive = timestampFrom(input.atExclusive, "atExclusive");
    const customerIds = parseDocumentIds(input.customerIds, "customerIds");
    if (customerIds.length === 0) {
      return {projectionVersion: ACCOUNT_ACTIVITY_PROJECTION_VERSION, balances: []};
    }
    const references = customerIds.map((customerId) => firestore.doc(
      businessPath(companyId, "customers", customerId),
    ));
    const customers = await firestore.getAll(...references);
    for (const customer of customers) {
      if (!customer.exists) {
        throw new HttpsError("not-found", "A requested customer was not found.");
      }
      if (user.role === "sales_rep" &&
          optionalString(customer.data()?.createdByUid) !== user.uid) {
        throw new HttpsError("permission-denied", "Customer access is denied.");
      }
    }
    const openings = await loadAccountOpenings(
      firestore,
      companyId,
      user.role === "admin" ? "all" : representativeScopeId(user.uid),
      customerIds.map((customerId) => `customer:${customerId}`),
      atExclusive,
    );
    return {
      projectionVersion: ACCOUNT_ACTIVITY_PROJECTION_VERSION,
      atExclusive: atExclusive.toMillis(),
      balances: openings.map((opening) => ({
        customerId: opening.accountKey.slice("customer:".length),
        balance: opening.balance,
        lastActivityAt: opening.lastActivityAt ?? null,
      })),
    };
  },
);

export async function reconcileFinancialLedgerAccountActivity(
  firestore: Firestore,
  companyId: string,
  entryId: string,
): Promise<void> {
  const entryRef = firestore.doc(
    businessPath(companyId, "financial_ledger_entries", entryId),
  );
  const stateRef = firestore.doc(
    businessPath(companyId, ACCOUNT_ACTIVITY_STATE_COLLECTION, entryId),
  );
  await firestore.runTransaction(async (transaction) => {
    const [entrySnapshot, stateSnapshot] = await transaction.getAll(entryRef, stateRef);
    const previous = stateSnapshot.exists
      ? parseAccountActivityState(stateSnapshot.data() ?? {})
      : null;
    const next = entrySnapshot.exists
      ? buildFinancialLedgerAccountActivity(entryId, entrySnapshot.data() ?? {})
      : null;
    applyFinancialLedgerAccountActivityChanges(
      transaction,
      firestore,
      companyId,
      entryId,
      previous,
      next,
    );
  });
}

export function buildFinancialLedgerAccountActivity(
  entryId: string,
  data: DocumentData,
): AccountActivityProjection {
  if (data.schemaVersion !== FINANCIAL_LEDGER_SCHEMA_VERSION) {
    throw new Error(
      `Financial ledger ${entryId} must use schemaVersion ` +
      `${FINANCIAL_LEDGER_SCHEMA_VERSION}.`,
    );
  }
  if (!(data.occurredAt instanceof Timestamp)) {
    throw new Error(`Financial ledger ${entryId} occurredAt must be a Timestamp.`);
  }
  const amount = finiteMoney(data.amount, "amount");
  if (amount <= 0) {
    throw new Error(`Financial ledger ${entryId} amount must be positive.`);
  }
  const activities = combineActivities([
    {
      accountKey: requiredScalarString(data.debitAccountKey, "debitAccountKey"),
      accountType: scalarString(data.debitAccountType, "debitAccountType"),
      accountName: scalarString(data.debitAccountName, "debitAccountName"),
      debit: amount,
      credit: 0,
      netChange: amount,
    },
    {
      accountKey: requiredScalarString(data.creditAccountKey, "creditAccountKey"),
      accountType: scalarString(data.creditAccountType, "creditAccountType"),
      accountName: scalarString(data.creditAccountName, "creditAccountName"),
      debit: 0,
      credit: amount,
      netChange: -amount,
    },
  ]);
  const dayKey = businessDayKey(data.occurredAt);
  const monthKey = dayKey.slice(0, 7);
  const shard = ledgerSummaryShard(entryId);
  const postingId = accountPostingId(entryId, data.occurredAt);
  const salesRepId = scalarString(
    data.salesRepId,
    "salesRepId",
    MAX_SALES_REP_ID_BYTES,
  );
  const fingerprint = createHash("sha256").update(JSON.stringify({
    occurredAtSeconds: data.occurredAt.seconds,
    occurredAtNanoseconds: data.occurredAt.nanoseconds,
    dayKey,
    monthKey,
    shard,
    postingId,
    salesRepId,
    activities,
  }), "utf8").digest("base64url");
  return {
    fingerprint,
    occurredAt: data.occurredAt,
    dayKey,
    monthKey,
    shard,
    postingId,
    salesRepId,
    activities,
  };
}

export function applyFinancialLedgerAccountActivityChanges(
  transaction: Transaction,
  firestore: Firestore,
  companyId: string,
  entryId: string,
  previous: AccountActivityState | null,
  next: AccountActivityProjection | null,
): void {
  if (previous?.fingerprint === next?.fingerprint) return;

  const aggregateDeltas = new Map<string, AccountDelta>();
  const postingChanges = new Map<string, DocumentData | null>();
  if (previous) {
    addProjectionChanges(
      companyId,
      entryId,
      previous,
      -1,
      aggregateDeltas,
      postingChanges,
    );
  }
  if (next) {
    addProjectionChanges(
      companyId,
      entryId,
      next,
      1,
      aggregateDeltas,
      postingChanges,
    );
  }
  for (const [path, delta] of aggregateDeltas) {
    transaction.set(firestore.doc(path), {
      projectionVersion: ACCOUNT_ACTIVITY_PROJECTION_VERSION,
      accountKey: delta.account.accountKey,
      accountType: delta.account.accountType,
      accountName: delta.account.accountName,
      entryCount: FieldValue.increment(delta.entryCount),
      debitTotal: FieldValue.increment(roundMoney(delta.debit)),
      creditTotal: FieldValue.increment(roundMoney(delta.credit)),
      netChange: FieldValue.increment(roundMoney(delta.netChange)),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  for (const [path, data] of postingChanges) {
    const postingRef = firestore.doc(path);
    if (data) transaction.set(postingRef, data);
    else transaction.delete(postingRef);
  }

  const stateRef = firestore.doc(
    businessPath(companyId, ACCOUNT_ACTIVITY_STATE_COLLECTION, entryId),
  );
  if (!next) {
    transaction.delete(stateRef);
    return;
  }
  transaction.set(stateRef, {
    projectionVersion: ACCOUNT_ACTIVITY_PROJECTION_VERSION,
    ledgerSchemaVersion: FINANCIAL_LEDGER_SCHEMA_VERSION,
    ledgerEntryId: entryId,
    fingerprint: next.fingerprint,
    occurredAt: next.occurredAt,
    dayKey: next.dayKey,
    monthKey: next.monthKey,
    shard: next.shard,
    postingId: next.postingId,
    salesRepId: next.salesRepId,
    activities: next.activities,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

export function combineOpeningActivity(
  accountKey: string,
  documents: DocumentData[],
): AccountOpening {
  let accountType = "";
  let accountName = "";
  let debit = 0;
  let credit = 0;
  for (const data of documents) {
    if (optionalString(data.accountKey) !== accountKey) {
      throw new Error("Account activity projection contains a mismatched account key.");
    }
    accountType ||= optionalString(data.accountType);
    accountName ||= optionalString(data.accountName);
    debit = roundMoney(debit + finiteMoney(data.debitTotal ?? data.debit, "debit"));
    credit = roundMoney(credit + finiteMoney(data.creditTotal ?? data.credit, "credit"));
  }
  return {
    accountKey,
    accountType,
    accountName,
    debit,
    credit,
    balance: roundMoney(debit - credit),
  };
}

async function loadAccountOpenings(
  firestore: Firestore,
  companyId: string,
  scope: string,
  accountKeys: string[],
  fromInclusive: Timestamp,
): Promise<AccountOpening[]> {
  const results: AccountOpening[] = [];
  for (let offset = 0; offset < accountKeys.length; offset += 10) {
    const batch = accountKeys.slice(offset, offset + 10);
    results.push(...await Promise.all(batch.map((accountKey) =>
      loadAccountOpening(
        firestore,
        companyId,
        scope,
        accountKey,
        fromInclusive,
      ))));
  }
  return results;
}

async function loadAccountOpening(
  firestore: Firestore,
  companyId: string,
  scope: string,
  accountKey: string,
  fromInclusive: Timestamp,
): Promise<AccountOpening> {
  const accountPath = accountActivityAccountPath(companyId, scope, accountKey);
  const dayKey = businessDayKey(fromInclusive);
  const monthKey = dayKey.slice(0, 7);
  const boundary = postingBoundaryId(dayKey, fromInclusive);
  const [months, days, postings] = await Promise.all([
    firestore.collection(`${accountPath}/months`)
      .where(FieldPath.documentId(), "<", `${monthKey}_s00`)
      .get(),
    firestore.collection(`${accountPath}/days`)
      .where(FieldPath.documentId(), ">=", `${monthKey}-01_s00`)
      .where(FieldPath.documentId(), "<", `${dayKey}_s00`)
      .get(),
    firestore.collection(`${accountPath}/postings`)
      .where(FieldPath.documentId(), ">=", `${dayKey}_`)
      .where(
        FieldPath.documentId(),
        "<",
        boundary,
      )
      .get(),
  ]);
  return combineOpeningActivity(accountKey, [
    ...months.docs.map((document) => document.data()),
    ...days.docs.map((document) => document.data()),
    ...postings.docs.map((document) => document.data()),
  ]);
}

function addProjectionChanges(
  companyId: string,
  entryId: string,
  projection: AccountActivityProjection,
  direction: -1 | 1,
  aggregateDeltas: Map<string, AccountDelta>,
  postingChanges: Map<string, DocumentData | null>,
): void {
  const scopes = ["all"];
  if (projection.salesRepId) {
    scopes.push(representativeScopeId(projection.salesRepId));
  }
  for (const scope of scopes) {
    for (const activity of projection.activities) {
      const accountPath = accountActivityAccountPath(
        companyId,
        scope,
        activity.accountKey,
      );
      addAggregateDelta(
        aggregateDeltas,
        `${accountPath}/months/${projection.monthKey}_${projection.shard}`,
        activity,
        direction,
      );
      addAggregateDelta(
        aggregateDeltas,
        `${accountPath}/days/${projection.dayKey}_${projection.shard}`,
        activity,
        direction,
      );
      const postingPath = `${accountPath}/postings/${projection.postingId}`;
      if (direction < 0) {
        postingChanges.set(postingPath, null);
      } else {
        postingChanges.set(postingPath, {
          projectionVersion: ACCOUNT_ACTIVITY_PROJECTION_VERSION,
          ledgerEntryId: entryId,
          occurredAt: projection.occurredAt,
          dayKey: projection.dayKey,
          accountKey: activity.accountKey,
          accountType: activity.accountType,
          accountName: activity.accountName,
          debit: activity.debit,
          credit: activity.credit,
          netChange: activity.netChange,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
  }
}

function addAggregateDelta(
  deltas: Map<string, AccountDelta>,
  path: string,
  activity: AccountActivity,
  direction: -1 | 1,
): void {
  const delta = deltas.get(path) ?? {
    account: activity,
    entryCount: 0,
    debit: 0,
    credit: 0,
    netChange: 0,
  };
  delta.account = activity;
  delta.entryCount += direction;
  delta.debit = roundMoney(delta.debit + activity.debit * direction);
  delta.credit = roundMoney(delta.credit + activity.credit * direction);
  delta.netChange = roundMoney(delta.netChange + activity.netChange * direction);
  deltas.set(path, delta);
}

function combineActivities(activities: AccountActivity[]): AccountActivity[] {
  const combined = new Map<string, AccountActivity>();
  for (const activity of activities) {
    const existing = combined.get(activity.accountKey);
    if (!existing) {
      combined.set(activity.accountKey, {...activity});
      continue;
    }
    existing.debit = roundMoney(existing.debit + activity.debit);
    existing.credit = roundMoney(existing.credit + activity.credit);
    existing.netChange = roundMoney(existing.netChange + activity.netChange);
    existing.accountType ||= activity.accountType;
    existing.accountName ||= activity.accountName;
  }
  return [...combined.values()].sort((a, b) =>
    a.accountKey.localeCompare(b.accountKey));
}

function parseAccountActivityState(data: DocumentData): AccountActivityState {
  if (data.projectionVersion !== ACCOUNT_ACTIVITY_PROJECTION_VERSION) {
    throw new Error("Account activity state has an incompatible projectionVersion.");
  }
  if (!(data.occurredAt instanceof Timestamp)) {
    throw new Error("Account activity state occurredAt must be a Timestamp.");
  }
  if (!Array.isArray(data.activities) || data.activities.length === 0) {
    throw new Error("Account activity state must contain activities.");
  }
  const activities = data.activities.map((value) => {
    const activity = record(value);
    return {
      accountKey: requiredScalarString(activity.accountKey, "accountKey"),
      accountType: scalarString(activity.accountType, "accountType"),
      accountName: scalarString(activity.accountName, "accountName"),
      debit: finiteMoney(activity.debit, "debit"),
      credit: finiteMoney(activity.credit, "credit"),
      netChange: finiteMoney(activity.netChange, "netChange"),
    };
  });
  return {
    fingerprint: requiredScalarString(data.fingerprint, "fingerprint"),
    occurredAt: data.occurredAt,
    dayKey: requiredScalarString(data.dayKey, "dayKey"),
    monthKey: requiredScalarString(data.monthKey, "monthKey"),
    shard: requiredScalarString(data.shard, "shard"),
    postingId: requiredScalarString(data.postingId, "postingId"),
    salesRepId: scalarString(data.salesRepId, "salesRepId"),
    activities,
  };
}

function parseAccountKeys(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > MAX_ACCOUNT_KEYS) {
    throw new HttpsError(
      "invalid-argument",
      `accountKeys must contain no more than ${MAX_ACCOUNT_KEYS} values.`,
    );
  }
  const result = [...new Set(value.map((item) =>
    requiredScalarString(item, "accountKeys[]")))];
  if (result.some((item) => Buffer.byteLength(item, "utf8") > MAX_ACCOUNT_KEY_BYTES)) {
    throw new HttpsError("invalid-argument", "An account key is too long.");
  }
  return result;
}

function parseDocumentIds(value: unknown, field: string): string[] {
  if (!Array.isArray(value) || value.length > MAX_ACCOUNT_KEYS) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must contain no more than ${MAX_ACCOUNT_KEYS} values.`,
    );
  }
  return [...new Set(value.map((item) => requiredDocumentId(item, `${field}[]`)))];
}

async function requireAccountActivityProjection(
  firestore: Firestore,
  companyId: string,
): Promise<void> {
  const metadata = await firestore.doc(businessPath(
    companyId,
    ACCOUNT_ACTIVITY_METADATA_COLLECTION,
    "current",
  )).get();
  if (!metadata.exists ||
      metadata.get("status") !== "ready" ||
      metadata.get("projectionVersion") !== ACCOUNT_ACTIVITY_PROJECTION_VERSION) {
    throw new HttpsError(
      "failed-precondition",
      "Financial ledger account activity projection is not ready.",
    );
  }
}

function accountActivityAccountPath(
  companyId: string,
  scope: string,
  accountKey: string,
): string {
  return `companies/${companyId}/${ACCOUNT_ACTIVITY_SCOPE_COLLECTION}/${scope}/` +
    `accounts/${accountKeyHash(accountKey)}`;
}

function accountKeyHash(accountKey: string): string {
  return `a_${createHash("sha256").update(accountKey, "utf8").digest("base64url")}`;
}

function representativeScopeId(salesRepId: string): string {
  const digest = createHash("sha256").update(salesRepId, "utf8").digest("base64url");
  return `rep_${digest}`;
}

function accountPostingId(entryId: string, occurredAt: Timestamp): string {
  const dayKey = businessDayKey(occurredAt);
  const suffix = createHash("sha256").update(entryId, "utf8")
    .digest("base64url").slice(0, 22);
  return `${dayKey}_${timestampSortKey(occurredAt)}_${suffix}`;
}

function postingBoundaryId(dayKey: string, value: Timestamp): string {
  return `${dayKey}_${timestampSortKey(value)}_`;
}

function timestampSortKey(value: Timestamp): string {
  return `${String(value.seconds).padStart(12, "0")}_` +
    String(value.nanoseconds).padStart(9, "0");
}

export function businessDayKey(value: Timestamp): string {
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

function finiteMoney(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`Account activity ${field} must be numeric.`);
  }
  return roundMoney(value);
}

function scalarString(value: unknown, field: string, maxBytes = 1_500): string {
  if (value === undefined || value === null) return "";
  if (typeof value !== "string") {
    throw new Error(`Account activity ${field} must be a string.`);
  }
  const result = value.trim();
  if (Buffer.byteLength(result, "utf8") > maxBytes) {
    throw new Error(`Account activity ${field} exceeds ${maxBytes} bytes.`);
  }
  return result;
}

function requiredScalarString(value: unknown, field: string): string {
  const result = scalarString(value, field);
  if (!result) throw new Error(`Account activity ${field} is required.`);
  return result;
}

function requiredDocumentId(value: unknown, field: string): string {
  const result = requiredScalarString(value, field);
  if (result.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return result;
}
