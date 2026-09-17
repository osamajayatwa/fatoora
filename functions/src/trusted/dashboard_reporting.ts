import {
  AggregateField,
  DocumentData,
  Firestore,
  Query,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {
  CallableRequest,
  HttpsError,
  onCall,
} from "firebase-functions/v2/https";
import {
  TRUSTED_CALLABLE_OPTIONS,
  businessPath,
  optionalString,
  record,
  requireCallableUid,
  requireTrustedUser,
  roundMoney,
  timestampFrom,
} from "./common";

export interface SalesTotals {
  totalSales: number;
  cashSales: number;
  creditSales: number;
  partialSales: number;
  invoiceCount: number;
}

export interface AggregateValue {
  count: number;
  amount: number;
}

export const getDashboardSnapshot = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    try {
      return await buildDashboardSnapshot(request);
    } catch (error) {
      if (isMissingDashboardIndexError(error)) {
        throw new HttpsError(
          "failed-precondition",
          "Dashboard reporting indexes are not ready.",
        );
      }
      throw error;
    }
  },
);

async function buildDashboardSnapshot(request: CallableRequest<unknown>) {
  const uid = requireCallableUid(request, "getDashboardSnapshot");
  const input = record(request.data);
  const companyId = optionalString(input.companyId);
  if (!companyId) throw new HttpsError("invalid-argument", "companyId is required.");
  const from = timestampFrom(input.from, "from");
  const to = timestampFrom(input.to, "to");
  if (from.toMillis() > to.toMillis()) {
    throw new HttpsError("invalid-argument", "Invalid dashboard date range.");
  }
  const firestore = getFirestore();
  const user = await firestore.runTransaction((transaction) =>
    requireTrustedUser(transaction, firestore, uid, companyId));
  const salesRepId = user.role === "sales_rep" ? user.uid : "";

  const [sales, receipts, expenses, receivables, cash, weekly] =
    await Promise.all([
      salesTotals(firestore, companyId, from, to, salesRepId),
      receiptTotals(firestore, companyId, from, to, salesRepId),
      expenseTotals(firestore, companyId, from, to, salesRepId),
      receivableTotals(firestore, companyId, salesRepId),
      cashTotals(firestore, companyId, user.role, user.uid),
      weeklySales(firestore, companyId, to, salesRepId),
    ]);

  let salesByRepSummary: DocumentData[] = [];
  if (user.role === "admin") {
    const reps = await firestore.collection("users")
      .where("companyId", "==", companyId)
      .where("role", "==", "sales_rep")
      .where("active", "==", true)
      .get();
    salesByRepSummary = await mapWithConcurrency(
      reps.docs,
      4,
      async (document) => {
        const rep = document.data();
        const [repSales, repReceipts, repCash] = await Promise.all([
          salesTotals(firestore, companyId, from, to, document.id),
          receiptTotals(firestore, companyId, from, to, document.id),
          cashTotals(firestore, companyId, "sales_rep", document.id),
        ]);
        return {
          salesRepId: document.id,
          salesRepName: optionalString(rep.name),
          ...repSales,
          receiptsCollected: repReceipts.amount,
          cashInHand: repCash.repCashOutstanding,
        };
      },
    );
    salesByRepSummary.sort((left, right) =>
      Number(right.totalSales) - Number(left.totalSales));
  } else {
    salesByRepSummary = [{
      salesRepId: user.uid,
      salesRepName: user.name,
      ...sales,
      receiptsCollected: receipts.amount,
      cashInHand: cash.repCashOutstanding,
    }];
  }

  return {
    ...sales,
    totalReceivables: receivables.amount,
    customerCount: receivables.customerCount,
    receiptCount: receipts.count,
    totalExpenses: expenses.posted,
    pendingExpenseCount: expenses.pendingCount,
    reimbursementsPayable: expenses.reimbursements,
    ...cash,
    weeklyInvoiceValues: weekly,
    salesByRepSummary,
    salesByRep: salesByRepSummary.map((row) => ({
      salesRepId: row.salesRepId,
      salesRepName: row.salesRepName,
      amount: row.totalSales,
    })),
    cashBySalesRep: salesByRepSummary.map((row) => ({
      salesRepId: row.salesRepId,
      salesRepName: row.salesRepName,
      amount: row.cashInHand,
    })),
  };
}

export function isMissingDashboardIndexError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const candidate = error as {code?: unknown; details?: unknown; message?: unknown};
  const isFailedPrecondition = candidate.code === 9 ||
    candidate.code === "failed-precondition";
  const detail = String(candidate.details ?? candidate.message ?? "");
  return isFailedPrecondition && detail.includes("requires an index");
}

async function salesTotals(
  firestore: Firestore,
  companyId: string,
  from: Timestamp,
  to: Timestamp,
  salesRepId: string,
): Promise<SalesTotals> {
  let invoiceQuery: Query = firestore.collection(
    companyCollectionPath(companyId, "invoices"),
  ).where("financialPosted", "==", true)
    .where("invoiceDate", ">=", from)
    .where("invoiceDate", "<=", to);
  let returnQuery: Query = firestore.collection(
    companyCollectionPath(companyId, "sales_returns"),
  ).where("financialPosted", "==", true)
    .where("status", "==", "confirmed")
    .where("returnDate", ">=", from)
    .where("returnDate", "<=", to);
  if (salesRepId) {
    invoiceQuery = invoiceQuery.where("salesRepId", "==", salesRepId);
    returnQuery = returnQuery.where("salesRepId", "==", salesRepId);
  }
  const paymentTypes = ["cash", "credit", "partial"];
  const [invoiceRows, returnRows, returnTotal] = await Promise.all([
    Promise.all(paymentTypes.map((type) => aggregateAmount(
      invoiceQuery.where("paymentType", "==", type),
      "grandTotal",
    ))),
    Promise.all(paymentTypes.map((type) => aggregateAmount(
      returnQuery.where("originalPaymentType", "==", type),
      "grandTotal",
    ))),
    aggregateAmount(returnQuery, "grandTotal"),
  ]);
  let resolvedReturns = returnRows;
  const classifiedCount = returnRows.reduce((sum, row) => sum + row.count, 0);
  if (classifiedCount !== returnTotal.count) {
    resolvedReturns = await legacyReturnTotals(
      firestore,
      companyId,
      returnQuery,
      paymentTypes,
    );
  }
  return combineSalesTotals(invoiceRows, resolvedReturns);
}

export function combineSalesTotals(
  invoiceRows: AggregateValue[],
  returnRows: AggregateValue[],
): SalesTotals {
  if (invoiceRows.length !== 3 || returnRows.length !== 3) {
    throw new Error("Dashboard sales totals require cash, credit, and partial buckets.");
  }
  const net = invoiceRows.map((row, index) =>
    roundMoney(row.amount - returnRows[index].amount));
  return {
    totalSales: roundMoney(net.reduce((sum, value) => sum + value, 0)),
    cashSales: net[0],
    creditSales: net[1],
    partialSales: net[2],
    invoiceCount: invoiceRows.reduce((sum, row) => sum + row.count, 0),
  };
}

async function legacyReturnTotals(
  firestore: Firestore,
  companyId: string,
  query: Query,
  paymentTypes: string[],
): Promise<AggregateValue[]> {
  const snapshot = await query.get();
  const invoiceIds = [...new Set(snapshot.docs
    .filter((document) => !paymentTypes.includes(optionalString(
      document.data().originalPaymentType,
    )))
    .map((document) => optionalString(document.data().originalInvoiceId))
    .filter(Boolean))];
  const invoiceTypes = new Map<string, string>();
  for (let start = 0; start < invoiceIds.length; start += 100) {
    const references = invoiceIds.slice(start, start + 100).map((id) =>
      firestore.doc(businessPath(companyId, "invoices", id)));
    if (references.length === 0) continue;
    const invoices = await firestore.getAll(...references);
    for (const invoice of invoices) {
      invoiceTypes.set(invoice.id, optionalString(invoice.data()?.paymentType));
    }
  }
  const result = paymentTypes.map(() => ({count: 0, amount: 0}));
  for (const document of snapshot.docs) {
    const data = document.data();
    const type = optionalString(data.originalPaymentType) ||
      invoiceTypes.get(optionalString(data.originalInvoiceId)) || "";
    const index = paymentTypes.indexOf(type);
    if (index < 0) continue;
    result[index].count += 1;
    result[index].amount = roundMoney(
      result[index].amount + finiteAggregateNumber(data.grandTotal),
    );
  }
  return result;
}

async function receiptTotals(
  firestore: Firestore,
  companyId: string,
  from: Timestamp,
  to: Timestamp,
  salesRepId: string,
): Promise<AggregateValue> {
  let query: Query = firestore.collection(companyCollectionPath(companyId, "receipts"))
    .where("receiptDate", ">=", from)
    .where("receiptDate", "<=", to);
  if (salesRepId) query = query.where("salesRepId", "==", salesRepId);
  return aggregateAmount(query, "amount");
}

async function expenseTotals(
  firestore: Firestore,
  companyId: string,
  from: Timestamp,
  to: Timestamp,
  salesRepId: string,
): Promise<{posted: number; pendingCount: number; reimbursements: number}> {
  let base: Query = firestore.collection(companyCollectionPath(companyId, "expenses"));
  if (salesRepId) base = base.where("paidByUid", "==", salesRepId);
  const [posted, pending, reimbursements] = await Promise.all([
    aggregateAmount(
      base.where("status", "in", ["posted", "approved"])
        .where("expenseDate", ">=", from)
        .where("expenseDate", "<=", to),
      "amount",
    ),
    base.where("status", "==", "pending").count().get(),
    aggregateAmount(
      base.where("reimbursementStatus", "==", "payable"),
      "amount",
    ),
  ]);
  return {
    posted: posted.amount,
    pendingCount: pending.data().count,
    reimbursements: reimbursements.amount,
  };
}

async function receivableTotals(
  firestore: Firestore,
  companyId: string,
  salesRepId: string,
): Promise<{amount: number; customerCount: number}> {
  let active: Query = firestore.collection(companyCollectionPath(companyId, "customers"))
    .where("active", "==", true);
  if (salesRepId) active = active.where("createdByUid", "==", salesRepId);
  const [customers, receivables] = await Promise.all([
    active.count().get(),
    active.where("currentBalance", ">", 0)
      .aggregate({amount: AggregateField.sum("currentBalance")}).get(),
  ]);
  return {
    amount: roundMoney(finiteAggregateNumber(receivables.data().amount)),
    customerCount: customers.data().count,
  };
}

async function cashTotals(
  firestore: Firestore,
  companyId: string,
  role: string,
  uid: string,
): Promise<{companyCash: number; repCashOutstanding: number; cashInHand: number}> {
  const balances = firestore.collection(companyCollectionPath(companyId, "cash_balances"));
  if (role === "sales_rep") {
    const snapshot = await balances.doc(`rep_${uid}`).get();
    const amount = roundMoney(finiteAggregateNumber(snapshot.data()?.amount));
    return {companyCash: 0, repCashOutstanding: amount, cashInHand: amount};
  }
  const [company, reps] = await Promise.all([
    balances.doc("company_cash").get(),
    balances.where("cashAccount", "==", "rep_cash")
      .aggregate({amount: AggregateField.sum("amount")}).get(),
  ]);
  const companyCash = roundMoney(finiteAggregateNumber(company.data()?.amount));
  const repCash = roundMoney(finiteAggregateNumber(reps.data().amount));
  return {
    companyCash,
    repCashOutstanding: repCash,
    cashInHand: companyCash,
  };
}

async function weeklySales(
  firestore: Firestore,
  companyId: string,
  through: Timestamp,
  salesRepId: string,
): Promise<number[]> {
  const days = dashboardDayRanges(through, Timestamp.now());
  return mapWithConcurrency(days, 4, async (day) => {
    let invoices: Query = firestore.collection(
      companyCollectionPath(companyId, "invoices"),
    ).where("financialPosted", "==", true)
      .where("invoiceDate", ">=", day.from)
      .where("invoiceDate", "<=", day.to);
    let returns: Query = firestore.collection(
      companyCollectionPath(companyId, "sales_returns"),
    ).where("financialPosted", "==", true)
      .where("status", "==", "confirmed")
      .where("returnDate", ">=", day.from)
      .where("returnDate", "<=", day.to);
    if (salesRepId) {
      invoices = invoices.where("salesRepId", "==", salesRepId);
      returns = returns.where("salesRepId", "==", salesRepId);
    }
    const [invoiceTotal, returnTotal] = await Promise.all([
      aggregateAmount(invoices, "grandTotal"),
      aggregateAmount(returns, "grandTotal"),
    ]);
    return roundMoney(invoiceTotal.amount - returnTotal.amount);
  });
}

export function dashboardDayRanges(
  through: Timestamp,
  now: Timestamp,
): Array<{from: Timestamp; to: Timestamp}> {
  // Jordan has observed permanent UTC+3 since October 2022. Using UTC fields on
  // shifted instants keeps Cloud Functions host timezone out of report buckets.
  const offsetMs = 3 * 60 * 60 * 1000;
  const endMillis = Math.min(through.toMillis(), now.toMillis());
  const shifted = new Date(endMillis + offsetMs);
  const endDayUtc = Date.UTC(
    shifted.getUTCFullYear(),
    shifted.getUTCMonth(),
    shifted.getUTCDate(),
  );
  const dayMs = 24 * 60 * 60 * 1000;
  return Array.from({length: 7}, (_, index) => {
    const startShifted = endDayUtc - (6 - index) * dayMs;
    const start = startShifted - offsetMs;
    return {
      from: Timestamp.fromMillis(start),
      to: Timestamp.fromMillis(start + dayMs - 1),
    };
  });
}

async function aggregateAmount(query: Query, field: string): Promise<AggregateValue> {
  const snapshot = await query.aggregate({
    count: AggregateField.count(),
    amount: AggregateField.sum(field),
  }).get();
  const data = snapshot.data();
  return {
    count: Number(data.count) || 0,
    amount: roundMoney(finiteAggregateNumber(data.amount)),
  };
}

function finiteAggregateNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function companyCollectionPath(companyId: string, collection: string): string {
  return `companies/${companyId}/${collection}`;
}

export async function mapWithConcurrency<T, R>(
  values: T[],
  concurrency: number,
  task: (value: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = [];
  for (let start = 0; start < values.length; start += concurrency) {
    results.push(...await Promise.all(
      values.slice(start, start + concurrency).map(task),
    ));
  }
  return results;
}
