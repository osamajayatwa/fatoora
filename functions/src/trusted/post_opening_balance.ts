import {FieldValue, Firestore, Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  TRUSTED_CALLABLE_OPTIONS,
  businessPath,
  finiteNumber,
  numberFrom,
  optionalString,
  record,
  requireCallableUid,
  requireTrustedUser,
  requiredString,
  roundMoney,
  timestampFrom,
} from "./common";

interface OpeningBalanceRequest {
  companyId?: unknown;
  customerId?: unknown;
  openingBalanceType?: unknown;
  amount?: unknown;
  transactionDate?: unknown;
  notes?: unknown;
}

export const postCustomerOpeningBalance = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    const uid = requireCallableUid(request, "postCustomerOpeningBalance");
    const input = record(request.data) as OpeningBalanceRequest;
    const companyId = requiredString(input.companyId, "companyId");
    const customerId = requiredString(input.customerId, "customerId");
    return postOpeningBalanceTransaction(
      getFirestore(),
      uid,
      companyId,
      customerId,
      input,
    );
  },
);

export async function postOpeningBalanceTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  customerId: string,
  input: OpeningBalanceRequest,
): Promise<{transactionId: string; balanceAfter: number; alreadyPosted: boolean}> {
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    const customerRef = firestore.doc(businessPath(companyId, "customers", customerId));
    const customerSnapshot = await transaction.get(customerRef);
    if (!customerSnapshot.exists) {
      throw new HttpsError("not-found", "Customer was not found.");
    }
    const customer = customerSnapshot.data() ?? {};
    if (customer.companyId !== companyId || customer.active !== true) {
      throw new HttpsError("failed-precondition", "Customer is inactive or invalid.");
    }
    if (user.role === "sales_rep" && customer.createdByUid !== user.uid) {
      throw new HttpsError("permission-denied", "Customer is not owned by this representative.");
    }
    const type = requiredString(input.openingBalanceType, "openingBalanceType");
    if (type !== "customer_owes" && type !== "customer_credit") {
      throw new HttpsError("invalid-argument", "Opening balance type is invalid.");
    }
    const amount = roundMoney(finiteNumber(input.amount, "amount"));
    if (amount <= 0) throw new HttpsError("invalid-argument", "Amount must be positive.");
    const transactionId = `${customerId}_opening_balance`;
    const ledgerRef = firestore.doc(
      businessPath(companyId, "customer_transactions", transactionId),
    );
    const existingLedger = await transaction.get(ledgerRef);
    if (existingLedger.exists) {
      const existing = existingLedger.data() ?? {};
      if (
        customer.lastOpeningBalanceTransactionId === transactionId &&
        existing.openingBalanceType === type &&
        roundMoney(numberFrom(existing, "amount")) === amount
      ) {
        return {
          transactionId,
          balanceAfter: roundMoney(numberFrom(existing, "balanceAfter")),
          alreadyPosted: true,
        };
      }
      throw new HttpsError("already-exists", "Customer already has a different opening balance.");
    }
    if (customer.lastOpeningBalanceTransactionId) {
      throw new HttpsError("already-exists", "Customer already has an opening balance.");
    }

    const before = roundMoney(numberFrom(customer, "currentBalance"));
    const signed = type === "customer_owes" ? amount : -amount;
    const after = roundMoney(before + signed);
    const transactionDate = timestampFrom(input.transactionDate, "transactionDate");
    const notes = optionalString(input.notes);

    transaction.update(customerRef, {
      currentBalance: after,
      lastOpeningBalanceTransactionId: transactionId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(ledgerRef, {
      id: transactionId,
      companyId,
      customerId,
      customerName: optionalString(customer.name),
      transactionType: "opening_balance",
      type: "opening_balance",
      sourceCollection: "customer_transactions",
      sourceId: transactionId,
      sourceNumber: "OPENING",
      transactionDate,
      debitAmount: type === "customer_owes" ? amount : 0,
      creditAmount: type === "customer_credit" ? amount : 0,
      balanceBefore: before,
      balanceAfter: after,
      openingBalanceType: type,
      amount,
      signedAmount: signed,
      invoiceId: "",
      invoiceNumber: "",
      returnInvoiceId: "",
      returnNumber: "",
      originalInvoiceId: "",
      originalInvoiceNumber: "",
      receiptId: "",
      receiptNumber: "",
      notes,
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      salesRepId: user.role === "sales_rep" ? user.uid : "",
      salesRepName: user.role === "sales_rep" ? user.name : "",
      createdAt: FieldValue.serverTimestamp(),
      referenceId: transactionId,
    });
    return {transactionId, balanceAfter: after, alreadyPosted: false};
  });
}

export function openingBalanceTimestamp(value: unknown): Timestamp {
  return timestampFrom(value, "transactionDate");
}
