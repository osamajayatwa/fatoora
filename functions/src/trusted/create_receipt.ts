import {
  FieldPath,
  FieldValue,
  Firestore,
  Query,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  TRUSTED_CALLABLE_OPTIONS,
  allocateDocumentNumber,
  businessPath,
  deterministicId,
  documentPrefix,
  finiteNumber,
  numberFrom,
  optionalString,
  permissionValue,
  record,
  requireCallableUid,
  requireTrustedUser,
  requiredIdempotencyKey,
  requiredString,
  roundMoney,
  timestampFrom,
} from "./common";
import {applyCashChange, CashAccount} from "./cash_ledger";
import {writeFinancialLedgerEntries} from "./financial_ledger";
import {
  buildReceiptFinancialLedgerEntries,
  receiptAllocationGroups,
} from "./financial_ledger_mappings";

export {receiptAllocationGroups} from "./financial_ledger_mappings";

interface ReceiptRequest {
  companyId?: unknown;
  idempotencyKey?: unknown;
  customerId?: unknown;
  amount?: unknown;
  paymentMethod?: unknown;
  receiptDate?: unknown;
  notes?: unknown;
  payFullBalance?: unknown;
}

export const createReceipt = onCall(TRUSTED_CALLABLE_OPTIONS, async (request) => {
  const uid = requireCallableUid(request, "createReceipt");
  const input = record(request.data) as ReceiptRequest;
  const companyId = requiredString(input.companyId, "companyId");
  const idempotencyKey = requiredIdempotencyKey(input.idempotencyKey);
  return createReceiptTransaction(
    getFirestore(),
    uid,
    companyId,
    idempotencyKey,
    input,
  );
});

export async function createReceiptTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  idempotencyKey: string,
  input: ReceiptRequest,
): Promise<{receiptId: string; receiptNumber: string; alreadyPosted: boolean}> {
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    const receiptId = deterministicId("receipt", idempotencyKey);
    const receiptRef = firestore.doc(businessPath(companyId, "receipts", receiptId));
    const existingReceipt = await transaction.get(receiptRef);
    if (existingReceipt.exists) {
      const existing = existingReceipt.data() ?? {};
      const requestedCustomerId = requiredString(input.customerId, "customerId");
      const requestedPayFull = input.payFullBalance === true;
      const requestedPaymentMethod = optionalString(input.paymentMethod).toLowerCase() || "cash";
      const requestedAmount = requestedPayFull
        ? numberFrom(existing, "amount")
        : roundMoney(finiteNumber(input.amount, "amount"));
      if (
        existing.createdByUid !== user.uid ||
        existing.companyId !== companyId ||
        existing.customerId !== requestedCustomerId ||
        existing.payFullBalance !== requestedPayFull ||
        existing.paymentMethod !== requestedPaymentMethod ||
        roundMoney(numberFrom(existing, "amount")) !== requestedAmount
      ) {
        throw new HttpsError("already-exists", "Idempotency key is already in use.");
      }
      return {
        receiptId,
        receiptNumber: optionalString(existing.receiptNumber),
        alreadyPosted: true,
      };
    }

    const customerId = requiredString(input.customerId, "customerId");
    const customerRef = firestore.doc(businessPath(companyId, "customers", customerId));
    const customerSnapshot = await transaction.get(customerRef);
    if (!customerSnapshot.exists) throw new HttpsError("not-found", "Customer was not found.");
    const customer = customerSnapshot.data() ?? {};
    if (customer.companyId !== companyId || customer.active !== true) {
      throw new HttpsError("failed-precondition", "Customer is inactive or invalid.");
    }
    if (user.role === "sales_rep" && customer.createdByUid !== user.uid) {
      throw new HttpsError("permission-denied", "Customer is not owned by this representative.");
    }
    const settingsRef = firestore.doc(businessPath(companyId, "settings", "app"));
    const settingsSnapshot = await transaction.get(settingsRef);
    const settings = settingsSnapshot.data();
    if (
      user.role === "sales_rep" &&
      !permissionValue(settings, "allowSalesRepCreateReceipts")
    ) {
      throw new HttpsError("permission-denied", "Receipt creation is disabled.");
    }
    const currentBalance = roundMoney(numberFrom(customer, "currentBalance"));
    const payFullBalance = input.payFullBalance === true;
    const amount = payFullBalance
      ? currentBalance
      : roundMoney(finiteNumber(input.amount, "amount"));
    if (amount <= 0 || amount > Math.max(currentBalance, 0)) {
      throw new HttpsError("failed-precondition", "Receipt exceeds customer receivable.");
    }
    const receiptDate = timestampFrom(input.receiptDate, "receiptDate");
    const paymentMethod = optionalString(input.paymentMethod).toLowerCase() || "cash";
    if (!["cash", "bank", "check", "cliq"].includes(paymentMethod)) {
      throw new HttpsError("invalid-argument", "Payment method is invalid.");
    }

    let invoicesQuery: Query = firestore
      .collection(`companies/${companyId}/invoices`)
      .where("customerId", "==", customerId)
      .where("financialPosted", "==", true);
    if (user.role === "sales_rep") {
      invoicesQuery = invoicesQuery.where("salesRepId", "==", user.uid);
    }
    invoicesQuery = invoicesQuery
      .orderBy("dueDate")
      .orderBy("invoiceDate")
      .orderBy(FieldPath.documentId());
    const invoiceSnapshots = await transaction.get(invoicesQuery);
    const allocation = allocateReceiptAmount(invoiceSnapshots.docs.map((doc) => ({
      id: doc.id,
      data: doc.data(),
    })), amount);

    const prefix = documentPrefix(settings, "receiptPrefix", "REC");
    const numberAllocation = await allocateDocumentNumber(
      transaction,
      firestore,
      companyId,
      "receipts",
      receiptDate,
      prefix,
    );
    const ledgerRef = firestore.doc(
      businessPath(companyId, "customer_transactions", `${receiptId}_credit`),
    );
    const cashRef = firestore.doc(
      businessPath(companyId, "cash_movements", `${receiptId}_cash_in`),
    );
    if ((await transaction.get(ledgerRef)).exists) {
      throw new HttpsError("data-loss", "Receipt ledger already exists without receipt.");
    }
    if (paymentMethod === "cash" && (await transaction.get(cashRef)).exists) {
      throw new HttpsError("data-loss", "Receipt cash movement already exists without receipt.");
    }

    const allocationGroups = receiptAllocationGroups(
      allocation.entries,
      allocation.unallocated,
      user.role === "sales_rep" ? user.uid : "",
      user.role === "sales_rep" ? user.name : "",
    );
    const assignedGroups = allocationGroups.filter((entry) => entry.salesRepId);
    const salesRepIds = [...new Set(assignedGroups.map((entry) => entry.salesRepId))];
    const salesRepId = assignedGroups.length === 1 && allocationGroups.length === 1
      ? assignedGroups[0].salesRepId
      : "";
    const salesRepName = salesRepId ? assignedGroups[0].salesRepName : "";
    const cashAccount: CashAccount = user.role === "admin" ? "company_cash" : "rep_cash";
    const cashBalance = paymentMethod === "cash"
      ? await applyCashChange(
        transaction,
        firestore,
        companyId,
        cashAccount,
        cashAccount === "rep_cash" ? user.uid : "",
        "in",
        amount,
        cashRef.id,
      )
      : undefined;
    const balanceAfter = roundMoney(currentBalance - amount);

    transaction.set(numberAllocation.counterRef, numberAllocation.counterData, {merge: true});
    for (const entry of allocation.entries) {
      const invoiceRef = firestore.doc(businessPath(companyId, "invoices", entry.id));
      const data = entry.data;
      const paidAmount = roundMoney(numberFrom(data, "paidAmount") + entry.amount);
      const remainingAmount = roundMoney(Math.max(numberFrom(data, "remainingAmount") - entry.amount, 0));
      const returnedReceivable = roundMoney(numberFrom(data, "returnedReceivableAmount"));
      const effectiveRemaining = roundMoney(Math.max(remainingAmount - returnedReceivable, 0));
      const receiptIds = Array.isArray(data.receiptIds) ? data.receiptIds : [];
      transaction.update(invoiceRef, {
        paidAmount,
        remainingAmount,
        paymentStatus: effectiveRemaining === 0 ? "paid" : "partiallyPaid",
        hasReceivedPayment: true,
        receiptIds: [...receiptIds, receiptId],
        lastReceiptId: receiptId,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    const invoiceAllocations = Object.fromEntries(
      allocation.entries.map((entry) => [entry.id, entry.amount]),
    );
    const invoiceAllocationDetails = allocation.entries.map((entry) => ({
      invoiceId: entry.id,
      invoiceNumber: optionalString(entry.data.invoiceNumber),
      amount: entry.amount,
    }));
    transaction.update(customerRef, {
      currentBalance: balanceAfter,
      totalPaid: roundMoney(numberFrom(customer, "totalPaid") + amount),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(receiptRef, {
      id: receiptId,
      companyId,
      receiptNumber: numberAllocation.number,
      receiptDate,
      customerId,
      customerSnapshot: customerSnapshotData(customerId, customer),
      amount,
      paymentMethod,
      notes: optionalString(input.notes),
      salesRepId,
      salesRepName,
      salesRepIds,
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      customerTransactionIds: [ledgerRef.id],
      cashMovementIds: paymentMethod === "cash" ? [cashRef.id] : [],
      invoiceAllocations,
      invoiceAllocationDetails,
      payFullBalance,
      idempotencyKey,
      resultingCustomerBalance: balanceAfter,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(ledgerRef, {
      id: ledgerRef.id,
      companyId,
      customerId,
      customerName: optionalString(customer.name),
      transactionType: "receipt",
      type: "payment",
      referenceId: receiptId,
      receiptId,
      receiptNumber: numberAllocation.number,
      invoiceAllocations,
      sourceCollection: "receipts",
      sourceId: receiptId,
      sourceNumber: numberAllocation.number,
      transactionDate: receiptDate,
      debitAmount: 0,
      creditAmount: amount,
      amount,
      signedAmount: -amount,
      balanceBefore: currentBalance,
      balanceAfter,
      notes: optionalString(input.notes),
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      salesRepId,
      salesRepName,
      createdAt: FieldValue.serverTimestamp(),
    });
    if (paymentMethod === "cash") {
      transaction.set(cashRef, {
        id: cashRef.id,
        companyId,
        movementType: "receipt",
        type: "receipt_cash",
        direction: "in",
        amount,
        cashAccount,
        balanceBefore: cashBalance?.before ?? 0,
        balanceAfter: cashBalance?.after ?? amount,
        paymentType: paymentMethod,
        customerId,
        customerName: optionalString(customer.name),
        referenceId: receiptId,
        referenceNumber: numberAllocation.number,
        sourceCollection: "receipts",
        sourceId: receiptId,
        sourceNumber: numberAllocation.number,
        date: receiptDate,
        movementDate: receiptDate,
        notes: optionalString(input.notes),
        salesRepId,
        salesRepName,
        createdByUid: user.uid,
        createdByName: user.name,
        createdByRole: user.role,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    writeFinancialLedgerEntries(
      transaction,
      firestore,
      buildReceiptFinancialLedgerEntries({
        companyId,
        receiptId,
        receiptNumber: numberAllocation.number,
        receiptDate,
        paymentMethod,
        cashAccount,
        cashAccountSalesRepId: user.uid,
        cashAccountSalesRepName: user.name,
        customerId,
        customerName: optionalString(customer.name),
        notes: optionalString(input.notes),
        groups: allocationGroups,
      }),
    );
    return {
      receiptId,
      receiptNumber: numberAllocation.number,
      alreadyPosted: false,
    };
  });
}

export function allocateReceiptAmount(
  invoices: Array<{id: string; data: Record<string, unknown>}>,
  amount: number,
): {entries: Array<{id: string; amount: number; data: Record<string, unknown>}>; unallocated: number} {
  let remaining = roundMoney(amount);
  const entries: Array<{id: string; amount: number; data: Record<string, unknown>}> = [];
  for (const invoice of invoices) {
    if (remaining <= 0) break;
    const data = invoice.data;
    if (
      data.invoiceStatus !== "confirmed" &&
      data.invoiceStatus !== "accepted"
    ) continue;
    const outstanding = roundMoney(Math.max(
      numberFrom(data, "remainingAmount") - numberFrom(data, "returnedReceivableAmount"),
      0,
    ));
    if (outstanding <= 0) continue;
    const applied = roundMoney(Math.min(remaining, outstanding));
    entries.push({id: invoice.id, amount: applied, data});
    remaining = roundMoney(remaining - applied);
  }
  return {entries, unallocated: remaining};
}

function customerSnapshotData(customerId: string, customer: Record<string, unknown>) {
  return {
    id: customerId,
    name: optionalString(customer.name),
    phone: optionalString(customer.phone),
    addressText: optionalString(customer.addressText),
    taxNumber: optionalString(customer.taxNumber),
  };
}

export function receiptTimestamp(value: unknown): Timestamp {
  return timestampFrom(value, "receiptDate");
}
