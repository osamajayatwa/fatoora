import {FieldValue, Firestore, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  TRUSTED_CALLABLE_OPTIONS,
  businessPath,
  deterministicId,
  finiteNumber,
  optionalString,
  record,
  requireCallableUid,
  requireTrustedUser,
  requiredIdempotencyKey,
  requiredString,
  roundMoney,
  timestampFrom,
} from "./common";
import {applyCashChange} from "./cash_ledger";

const categories = new Set([
  "fuel", "parking", "maintenance", "delivery", "meals", "office",
  "utilities", "salary", "rent", "other",
]);

interface CreateExpenseRequest {
  companyId?: unknown;
  idempotencyKey?: unknown;
  amount?: unknown;
  expenseDate?: unknown;
  category?: unknown;
  customCategoryName?: unknown;
  description?: unknown;
  fundingSource?: unknown;
}

interface ExpenseDecisionRequest {
  companyId?: unknown;
  expenseId?: unknown;
}

export const createExpense = onCall(TRUSTED_CALLABLE_OPTIONS, async (request) => {
  const uid = requireCallableUid(request, "createExpense");
  const input = record(request.data) as CreateExpenseRequest;
  const companyId = requiredString(input.companyId, "companyId");
  const key = requiredIdempotencyKey(input.idempotencyKey);
  return createExpenseTransaction(getFirestore(), uid, companyId, key, input);
});

export const approveExpense = onCall(TRUSTED_CALLABLE_OPTIONS, async (request) => {
  const uid = requireCallableUid(request, "approveExpense");
  const input = record(request.data) as ExpenseDecisionRequest;
  const companyId = requiredString(input.companyId, "companyId");
  const expenseId = requiredString(input.expenseId, "expenseId");
  return approveExpenseTransaction(getFirestore(), uid, companyId, expenseId);
});

export async function createExpenseTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  idempotencyKey: string,
  input: CreateExpenseRequest,
): Promise<{expenseId: string; alreadyPosted: boolean}> {
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    const expenseId = deterministicId("expense", idempotencyKey);
    const expenseRef = firestore.doc(businessPath(companyId, "expenses", expenseId));
    const amount = roundMoney(finiteNumber(input.amount, "amount"));
    if (amount <= 0) throw new HttpsError("invalid-argument", "Amount must be positive.");
    const category = requiredString(input.category, "category");
    if (!categories.has(category)) {
      throw new HttpsError("invalid-argument", "Expense category is invalid.");
    }
    const customCategoryName = optionalString(input.customCategoryName);
    if (category === "other" && !customCategoryName) {
      throw new HttpsError("invalid-argument", "Custom category is required.");
    }
    const requestedSource = requiredString(input.fundingSource, "fundingSource");
    const fundingSource = user.role === "admin" ? "company_cash" : requestedSource;
    if (
      user.role === "sales_rep" &&
      fundingSource !== "rep_collected_cash" &&
      fundingSource !== "personal_cash"
    ) {
      throw new HttpsError("permission-denied", "Expense funding source is not permitted.");
    }
    const expenseDate = timestampFrom(input.expenseDate, "expenseDate");
    const existing = await transaction.get(expenseRef);
    if (existing.exists) {
      const data = existing.data() ?? {};
      if (
        data.createdByUid !== user.uid ||
        data.companyId !== companyId ||
        roundMoney(typeof data.amount === "number" ? data.amount : 0) !== amount ||
        data.category !== category ||
        data.fundingSource !== fundingSource
      ) {
        throw new HttpsError("already-exists", "Idempotency key is already in use.");
      }
      return {expenseId, alreadyPosted: true};
    }
    const immediate = user.role === "admin";
    const movementRef = firestore.doc(
      businessPath(companyId, "cash_movements", `${expenseId}_cash_out`),
    );
    if (immediate && (await transaction.get(movementRef)).exists) {
      throw new HttpsError("data-loss", "Expense cash movement exists without expense.");
    }
    const cashBalance = immediate
      ? await applyCashChange(
        transaction,
        firestore,
        companyId,
        "company_cash",
        "",
        "out",
        amount,
        movementRef.id,
      )
      : undefined;
    const description = optionalString(input.description);
    transaction.set(expenseRef, {
      id: expenseId,
      companyId,
      amount,
      expenseDate,
      category,
      categoryName: category,
      customCategoryName,
      description,
      notes: description,
      paidByUid: user.uid,
      paidByName: user.name,
      paidByRole: user.role,
      salesRepId: user.role === "sales_rep" ? user.uid : "",
      salesRepName: user.role === "sales_rep" ? user.name : "",
      paymentMethod: "cash",
      fundingSource,
      status: immediate ? "posted" : "pending",
      cashMovementId: immediate ? movementRef.id : "",
      reimbursementStatus: "none",
      approvedByUid: immediate ? user.uid : "",
      approvedByName: immediate ? user.name : "",
      ...(immediate ? {approvedAt: FieldValue.serverTimestamp()} : {}),
      rejectedByUid: "",
      rejectedByName: "",
      rejectionReason: "",
      idempotencyKey,
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (immediate) {
      transaction.set(movementRef, expenseCashMovement({
        id: movementRef.id,
        companyId,
        amount,
        cashAccount: "company_cash",
        balanceBefore: cashBalance?.before ?? 0,
        balanceAfter: cashBalance?.after ?? 0,
        expenseId,
        expenseDate,
        description,
        salesRepId: "",
        salesRepName: "",
        actorUid: user.uid,
        actorName: user.name,
        actorRole: user.role,
      }));
    }
    return {expenseId, alreadyPosted: false};
  });
}

export async function approveExpenseTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  expenseId: string,
): Promise<{expenseId: string; alreadyPosted: boolean}> {
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    if (user.role !== "admin") {
      throw new HttpsError("permission-denied", "Only administrators can approve expenses.");
    }
    const expenseRef = firestore.doc(businessPath(companyId, "expenses", expenseId));
    const snapshot = await transaction.get(expenseRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Expense was not found.");
    const expense = snapshot.data() ?? {};
    if (expense.status === "approved" || expense.status === "posted") {
      return {expenseId, alreadyPosted: true};
    }
    if (expense.status !== "pending") {
      throw new HttpsError("failed-precondition", "Expense is not pending.");
    }
    if (expense.fundingSource === "personal_cash") {
      transaction.update(expenseRef, {
        status: "approved",
        cashMovementId: "",
        reimbursementStatus: "payable",
        approvedByUid: user.uid,
        approvedByName: user.name,
        approvedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {expenseId, alreadyPosted: false};
    }
    if (expense.fundingSource !== "rep_collected_cash") {
      throw new HttpsError("failed-precondition", "Expense funding source is invalid.");
    }
    const salesRepId = requiredString(expense.salesRepId, "salesRepId");
    const amount = roundMoney(typeof expense.amount === "number" ? expense.amount : 0);
    if (amount <= 0) throw new HttpsError("data-loss", "Expense amount is invalid.");
    const movementRef = firestore.doc(
      businessPath(companyId, "cash_movements", `${expenseId}_cash_out`),
    );
    if ((await transaction.get(movementRef)).exists) {
      throw new HttpsError("data-loss", "Expense movement exists without approval.");
    }
    const cashBalance = await applyCashChange(
      transaction,
      firestore,
      companyId,
      "rep_cash",
      salesRepId,
      "out",
      amount,
      movementRef.id,
    );
    transaction.set(movementRef, expenseCashMovement({
      id: movementRef.id,
      companyId,
      amount,
      cashAccount: "rep_cash",
      balanceBefore: cashBalance.before,
      balanceAfter: cashBalance.after,
      expenseId,
      expenseDate: expense.expenseDate,
      description: optionalString(expense.description) || optionalString(expense.notes),
      salesRepId,
      salesRepName: optionalString(expense.salesRepName),
      actorUid: user.uid,
      actorName: user.name,
      actorRole: user.role,
    }));
    transaction.update(expenseRef, {
      status: "approved",
      cashMovementId: movementRef.id,
      reimbursementStatus: "none",
      approvedByUid: user.uid,
      approvedByName: user.name,
      approvedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {expenseId, alreadyPosted: false};
  });
}

function expenseCashMovement(input: {
  id: string;
  companyId: string;
  amount: number;
  cashAccount: string;
  balanceBefore: number;
  balanceAfter: number;
  expenseId: string;
  expenseDate: unknown;
  description: string;
  salesRepId: string;
  salesRepName: string;
  actorUid: string;
  actorName: string;
  actorRole: string;
}) {
  return {
    id: input.id,
    companyId: input.companyId,
    movementType: "expense",
    type: "expense_cash",
    direction: "out",
    amount: input.amount,
    cashAccount: input.cashAccount,
    balanceBefore: input.balanceBefore,
    balanceAfter: input.balanceAfter,
    customerId: "",
    customerName: "",
    referenceId: input.expenseId,
    referenceNumber: input.expenseId,
    sourceCollection: "expenses",
    sourceId: input.expenseId,
    sourceNumber: input.expenseId,
    date: input.expenseDate,
    movementDate: input.expenseDate,
    notes: input.description,
    salesRepId: input.salesRepId,
    salesRepName: input.salesRepName,
    createdByUid: input.actorUid,
    createdByName: input.actorName,
    createdByRole: input.actorRole,
    createdAt: FieldValue.serverTimestamp(),
  };
}
