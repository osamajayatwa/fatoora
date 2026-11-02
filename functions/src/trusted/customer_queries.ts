import {
  DocumentData, FieldPath, Filter, Firestore, Query, QueryDocumentSnapshot,
  Timestamp, Transaction, getFirestore,
} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {customerAssignedTo} from "./customer_assignment";
import {
  TRUSTED_CALLABLE_OPTIONS, TrustedUser, optionalString, record,
  requireCallableUid, requireTrustedUser, requiredString, roundMoney,
} from "./common";

// Firestore cannot query for absent assignment fields. Creator candidates must
// therefore be authorized on the server BEFORE forming a page, not filtered by
// the client after limit(). Versioned assignment always supersedes the creator.
export function accessibleCustomerCandidates(
  firestore: Firestore, companyId: string, salesRepId: string,
): Query {
  const customers = firestore.collection(`companies/${companyId}/customers`);
  return salesRepId ? customers.where(Filter.or(
    Filter.where("createdByUid", "==", salesRepId),
    Filter.and(Filter.where("assignmentVersion", "==", 1), Filter.where("assignedToUid", "==", salesRepId)),
  )) : customers;
}

export async function customerPortfolioTotals(
  transaction: Transaction, firestore: Firestore, companyId: string, salesRepId: string,
): Promise<{amount: number; customerCount: number}> {
  const base = accessibleCustomerCandidates(firestore, companyId, salesRepId)
    .where("active", "==", true).orderBy(FieldPath.documentId());
  let query = base;
  let amount = 0;
  let customerCount = 0;
  while (true) {
    const page = await transaction.get(query.limit(200));
    for (const doc of page.docs) {
      const data = doc.data();
      if (salesRepId && !customerAssignedTo(data, salesRepId)) continue;
      customerCount++;
      if (typeof data.currentBalance === "number" && Number.isFinite(data.currentBalance) && data.currentBalance > 0) {
        amount += data.currentBalance;
      }
    }
    if (page.size < 200) break;
    query = base.startAfter(page.docs[page.size - 1]);
  }
  return {amount: roundMoney(amount), customerCount};
}

export const listAccessibleCustomers = onCall(TRUSTED_CALLABLE_OPTIONS, async (request) => {
  const uid = requireCallableUid(request, "listAccessibleCustomers");
  return listAccessibleCustomersPage(getFirestore(), uid, record(request.data));
});

export async function listAccessibleCustomersPage(firestore: Firestore, uid: string | undefined, input: DocumentData) {
  const companyId = requiredString(input.companyId, "companyId");
  if (companyId.includes("/")) throw new HttpsError("invalid-argument", "Invalid companyId.");
  const pageSize = input.pageSize ?? 50;
  if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 200) {
    throw new HttpsError("invalid-argument", "pageSize must be between 1 and 200.");
  }
  const order = input.order ?? "name";
  if (!["name", "balance", "id"].includes(order)) throw new HttpsError("invalid-argument", "Invalid customer order.");
  const search = optionalString(input.searchText).toLowerCase();
  if (search.length > 200) throw new HttpsError("invalid-argument", "Search is too long.");
  if (order !== "name" && search) throw new HttpsError("invalid-argument", "Search requires name order.");
  const activeOnly = input.activeOnly !== false;
  const cursor = input.after == null ? null : record(input.after);
  // The cursor contains only an ordering boundary, never authorization. Bind it
  // to the query so reusing a name cursor for balances cannot silently skip data.
  const scope = JSON.stringify([companyId, uid, order, activeOnly, search]);
  if (cursor && (cursor.scope !== scope || typeof cursor.id !== "string" || !cursor.id || cursor.id.includes("/") ||
      (order === "name" && typeof cursor.value !== "string") ||
      (order === "balance" && (typeof cursor.value !== "number" || !Number.isFinite(cursor.value))))) {
    throw new HttpsError("invalid-argument", "Invalid customer cursor.");
  }
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    const salesRepId = user.role === "sales_rep" ? user.uid : "";
    let base = accessibleCustomerCandidates(firestore, companyId, salesRepId);
    if (activeOnly) base = base.where("active", "==", true);
    if (search) base = base.where("searchKeywords", "array-contains", search);
    if (order === "balance") base = base.where("currentBalance", ">", 0).orderBy("currentBalance", "desc");
    if (order === "name") base = base.orderBy("nameLower");
    base = base.orderBy(FieldPath.documentId());
    let query = cursor ? (order === "id" ? base.startAfter(cursor.id) : base.startAfter(cursor.value, cursor.id)) : base;
    const documents: QueryDocumentSnapshot[] = [];
    // Fill through skipped transferred records, including an authorized lookahead.
    // Memory stays bounded by pageSize; no entire collection reaches the client.
    while (documents.length <= pageSize) {
      const batch = await transaction.get(query.limit(pageSize + 1));
      for (const doc of batch.docs) {
        if (canAccessCustomer(user, doc.data())) documents.push(doc);
        if (documents.length > pageSize) break;
      }
      if (documents.length > pageSize || batch.size < pageSize + 1) break;
      query = base.startAfter(batch.docs[batch.size - 1]);
    }
    const hasMore = documents.length > pageSize;
    const page = documents.slice(0, pageSize);
    const last = page[page.length - 1];
    const totals = input.includeTotals === true ?
      await customerPortfolioTotals(transaction, firestore, companyId, salesRepId) : undefined;
    return {
      customers: page.map((doc) => customerWireData(doc)), hasMore,
      cursor: last ? {scope, id: last.id, value: order === "balance" ? last.get("currentBalance") :
        order === "name" ? last.get("nameLower") : last.id} : null,
      ...(totals ? {totalReceivables: totals.amount, customerCount: totals.customerCount} : {}),
    };
  }, {readOnly: true});
}

function canAccessCustomer(user: TrustedUser, customer: DocumentData): boolean {
  return user.role === "admin" || customerAssignedTo(customer, user.uid);
}

function customerWireData(doc: QueryDocumentSnapshot): DocumentData {
  const data = doc.data();
  // Callables do not deserialize Admin SDK Timestamps as Flutter Timestamps.
  return {...data, id: doc.id,
    createdAt: data.createdAt instanceof Timestamp ? data.createdAt.toDate().toISOString() : data.createdAt ?? null,
    updatedAt: data.updatedAt instanceof Timestamp ? data.updatedAt.toDate().toISOString() : data.updatedAt ?? null};
}
