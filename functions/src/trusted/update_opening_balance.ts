import {FieldValue, Firestore, Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  TRUSTED_CALLABLE_OPTIONS,
  businessPath,
  deterministicId,
  finiteNumber,
  numberFrom,
  optionalString,
  record,
  requireCallableUid,
  requireTrustedUser,
  requiredIdempotencyKey,
  requiredString,
  roundMoney,
} from "./common";
import {writeFinancialLedgerEntries} from "./financial_ledger";
import {buildCustomerOpeningFinancialLedgerEntry} from "./financial_ledger_mappings";

interface UpdateOpeningBalanceRequest {
  companyId?: unknown;
  customerId?: unknown;
  idempotencyKey?: unknown;
  openingBalanceType?: unknown;
  amount?: unknown;
  reason?: unknown;
}

interface UpdateOpeningBalanceResult {
  transactionId: string;
  adjustmentTransactionId: string;
  balanceAfter: number;
  difference: number;
  alreadyPosted: boolean;
}

export const updateCustomerOpeningBalance = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    const uid = requireCallableUid(request, "updateCustomerOpeningBalance");
    const input = record(request.data) as UpdateOpeningBalanceRequest;
    const companyId = requiredString(input.companyId, "companyId");
    const customerId = requiredDocumentId(input.customerId, "customerId");
    const idempotencyKey = requiredIdempotencyKey(input.idempotencyKey);
    return updateOpeningBalanceTransaction(
      getFirestore(),
      uid,
      companyId,
      customerId,
      idempotencyKey,
      input,
    );
  },
);

export async function updateOpeningBalanceTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  customerId: string,
  idempotencyKey: string,
  input: UpdateOpeningBalanceRequest,
): Promise<UpdateOpeningBalanceResult> {
  const newType = requiredString(
    input.openingBalanceType,
    "openingBalanceType",
  );
  if (newType !== "customer_owes" && newType !== "customer_credit") {
    throw new HttpsError("invalid-argument", "Opening balance type is invalid.");
  }
  const newAbsoluteAmount = roundMoney(finiteNumber(input.amount, "amount"));
  if (newAbsoluteAmount <= 0 || newAbsoluteAmount > 999999999) {
    throw new HttpsError("invalid-argument", "Amount must be positive and valid.");
  }
  const reason = requiredString(input.reason, "reason");
  if (reason.length > 500) {
    throw new HttpsError("invalid-argument", "Reason must not exceed 500 characters.");
  }
  const newSignedAmount = newType === "customer_owes"
    ? newAbsoluteAmount
    : -newAbsoluteAmount;
  const adjustmentTransactionId = deterministicId(
    "opening_balance_adjustment",
    idempotencyKey,
  );

  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    const customerRef = firestore.doc(
      businessPath(companyId, "customers", customerId),
    );
    const customerSnapshot = await transaction.get(customerRef);
    if (!customerSnapshot.exists) {
      throw new HttpsError("not-found", "Customer was not found.");
    }
    const customer = customerSnapshot.data() ?? {};
    if (customer.companyId !== companyId || customer.active !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Customer is inactive or invalid.",
      );
    }
    if (user.role === "sales_rep" && customer.createdByUid !== user.uid) {
      throw new HttpsError(
        "permission-denied",
        "Customer is not owned by this representative.",
      );
    }

    const transactionId = openingBalanceReference(customer, customerId);
    const openingRef = firestore.doc(
      businessPath(companyId, "customer_transactions", transactionId),
    );
    const adjustmentRef = firestore.doc(
      businessPath(
        companyId,
        "customer_transactions",
        adjustmentTransactionId,
      ),
    );
    const [openingSnapshot, adjustmentSnapshot] = await transaction.getAll(
      openingRef,
      adjustmentRef,
    );
    if (!openingSnapshot.exists) {
      throw new HttpsError("not-found", "Opening balance was not found.");
    }
    const opening = openingSnapshot.data() ?? {};
    validateOpeningBalance(opening, companyId, customerId, transactionId);

    if (adjustmentSnapshot.exists) {
      const adjustment = adjustmentSnapshot.data() ?? {};
      if (
        adjustment.idempotencyKey !== idempotencyKey ||
        adjustment.customerId !== customerId ||
        adjustment.adjustedByUid !== user.uid ||
        adjustment.originalOpeningBalanceReference !== transactionId ||
        roundMoney(numberFrom(adjustment, "newAmount")) !== newSignedAmount ||
        optionalString(adjustment.reason) !== reason
      ) {
        throw new HttpsError(
          "already-exists",
          "Idempotency key is already in use.",
          {reason: "idempotency-conflict"},
        );
      }
      return {
        transactionId,
        adjustmentTransactionId,
        balanceAfter: roundMoney(numberFrom(adjustment, "balanceAfter")),
        difference: roundMoney(numberFrom(adjustment, "difference")),
        alreadyPosted: true,
      };
    }

    const oldSignedAmount = signedOpeningBalance(opening);
    const difference = roundMoney(newSignedAmount - oldSignedAmount);
    if (difference === 0) {
      throw new HttpsError(
        "invalid-argument",
        "The new opening balance must be different from the old balance.",
        {reason: "no-change"},
      );
    }
    const balanceBefore = roundMoney(numberFrom(customer, "currentBalance"));
    const balanceAfter = roundMoney(balanceBefore + difference);

    transaction.update(customerRef, {
      currentBalance: balanceAfter,
      openingBalance: newSignedAmount,
      lastOpeningBalanceTransactionId: transactionId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    // debitAmount/creditAmount on the original row remain the immutable amount
    // it initially posted. The adjustment row below carries the difference, so
    // existing statement summation stays correct without double counting.
    transaction.update(openingRef, {
      openingBalanceType: newType,
      amount: newAbsoluteAmount,
      signedAmount: newSignedAmount,
      lastAdjustmentTransactionId: adjustmentTransactionId,
      lastAdjustedByUid: user.uid,
      lastAdjustedByName: user.name,
      lastAdjustedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(adjustmentRef, {
      id: adjustmentTransactionId,
      companyId,
      customerId,
      customerName: optionalString(customer.name),
      transactionType: "opening_balance_adjustment",
      type: "opening_balance_adjustment",
      sourceCollection: "customer_transactions",
      sourceId: transactionId,
      sourceNumber: "OPENING-ADJ",
      transactionDate: FieldValue.serverTimestamp(),
      debitAmount: difference > 0 ? difference : 0,
      creditAmount: difference < 0 ? -difference : 0,
      balanceBefore,
      balanceAfter,
      openingBalanceType: newType,
      amount: Math.abs(difference),
      signedAmount: difference,
      oldAmount: oldSignedAmount,
      newAmount: newSignedAmount,
      difference,
      reason,
      adjustedByUid: user.uid,
      adjustedAt: FieldValue.serverTimestamp(),
      originalOpeningBalanceReference: transactionId,
      oldOpeningBalanceType: openingBalanceType(opening, oldSignedAmount),
      newOpeningBalanceType: newType,
      oldAbsoluteAmount: Math.abs(oldSignedAmount),
      newAbsoluteAmount,
      idempotencyKey,
      invoiceId: "",
      invoiceNumber: "",
      returnInvoiceId: "",
      returnNumber: "",
      originalInvoiceId: "",
      originalInvoiceNumber: "",
      receiptId: "",
      receiptNumber: "",
      notes: reason,
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      salesRepId: user.role === "sales_rep" ? user.uid : "",
      salesRepName: user.role === "sales_rep" ? user.name : "",
      createdAt: FieldValue.serverTimestamp(),
      referenceId: transactionId,
    });
    const salesRepId = user.role === "sales_rep" ? user.uid : "";
    const salesRepName = user.role === "sales_rep" ? user.name : "";
    writeFinancialLedgerEntries(transaction, firestore, [
      buildCustomerOpeningFinancialLedgerEntry({
        companyId,
        transactionId: adjustmentTransactionId,
        transactionDate: Timestamp.now(),
        transactionType: "opening_balance_adjustment",
        openingBalanceType: newType,
        signedAmount: difference,
        customerId,
        customerName: optionalString(customer.name),
        salesRepId,
        salesRepName,
        notes: reason,
      }),
    ]);
    return {
      transactionId,
      adjustmentTransactionId,
      balanceAfter,
      difference,
      alreadyPosted: false,
    };
  });
}

function openingBalanceReference(
  customer: Record<string, unknown>,
  customerId: string,
): string {
  const stored = optionalString(customer.lastOpeningBalanceTransactionId);
  const reference = stored || `${customerId}_opening_balance`;
  if (reference.includes("/") || reference.length > 1500) {
    throw new HttpsError(
      "failed-precondition",
      "Opening balance reference is invalid.",
    );
  }
  return reference;
}

function validateOpeningBalance(
  opening: Record<string, unknown>,
  companyId: string,
  customerId: string,
  transactionId: string,
): void {
  if (
    opening.id !== transactionId ||
    opening.companyId !== companyId ||
    opening.customerId !== customerId ||
    (opening.transactionType !== "opening_balance" &&
      opening.type !== "opening_balance")
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Opening balance record is invalid.",
    );
  }
}

function signedOpeningBalance(opening: Record<string, unknown>): number {
  if (
    typeof opening.signedAmount === "number" &&
    Number.isFinite(opening.signedAmount)
  ) {
    const signed = roundMoney(opening.signedAmount);
    if (signed !== 0) return signed;
  }
  const ledgerSigned = roundMoney(
    numberFrom(opening, "debitAmount") - numberFrom(opening, "creditAmount"),
  );
  if (ledgerSigned !== 0) return ledgerSigned;
  const amount = roundMoney(numberFrom(opening, "amount"));
  const type = optionalString(opening.openingBalanceType);
  if (amount > 0 && (type === "customer_owes" || type === "customer_credit")) {
    return type === "customer_owes" ? amount : -amount;
  }
  throw new HttpsError(
    "failed-precondition",
    "Opening balance amount is invalid.",
  );
}

function openingBalanceType(
  opening: Record<string, unknown>,
  signedAmount: number,
): string {
  const stored = optionalString(opening.openingBalanceType);
  if (stored === "customer_owes" || stored === "customer_credit") return stored;
  return signedAmount > 0 ? "customer_owes" : "customer_credit";
}

function requiredDocumentId(value: unknown, field: string): string {
  const id = requiredString(value, field);
  if (id.includes("/") || id.length > 1500) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return id;
}
