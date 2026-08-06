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
import {readCashBalance, writeCashBalance} from "./cash_ledger";

interface SettlementRequest {
  companyId?: unknown;
  idempotencyKey?: unknown;
  salesRepId?: unknown;
  salesRepName?: unknown;
  amount?: unknown;
  settlementDate?: unknown;
  notes?: unknown;
}

export const recordCashSettlement = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    const uid = requireCallableUid(request, "recordCashSettlement");
    const input = record(request.data) as SettlementRequest;
    const companyId = requiredString(input.companyId, "companyId");
    const key = requiredIdempotencyKey(input.idempotencyKey);
    return recordCashSettlementTransaction(
      getFirestore(),
      uid,
      companyId,
      key,
      input,
    );
  },
);

export async function recordCashSettlementTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  idempotencyKey: string,
  input: SettlementRequest,
): Promise<{settlementId: string; alreadyPosted: boolean}> {
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    if (user.role !== "admin") {
      throw new HttpsError("permission-denied", "Only administrators can settle cash.");
    }
    const salesRepId = requiredString(input.salesRepId, "salesRepId");
    const repSnapshot = await transaction.get(firestore.doc(`users/${salesRepId}`));
    const rep = repSnapshot.data() ?? {};
    if (
      !repSnapshot.exists ||
      rep.role !== "sales_rep" ||
      rep.active !== true ||
      rep.approvalStatus !== "approved" ||
      rep.companyId !== companyId
    ) {
      throw new HttpsError("failed-precondition", "Representative is not active and approved.");
    }
    const salesRepName = optionalString(rep.name) ||
      optionalString(input.salesRepName) || salesRepId;
    const amount = roundMoney(finiteNumber(input.amount, "amount"));
    if (amount <= 0) throw new HttpsError("invalid-argument", "Amount must be positive.");
    const date = timestampFrom(input.settlementDate, "settlementDate");
    const settlementId = deterministicId("settlement", idempotencyKey);
    const settlementRef = firestore.doc(
      businessPath(companyId, "settlements", settlementId),
    );
    const existing = await transaction.get(settlementRef);
    if (existing.exists) {
      const data = existing.data() ?? {};
      if (
        data.salesRepId !== salesRepId ||
        roundMoney(typeof data.amount === "number" ? data.amount : 0) !== amount
      ) {
        throw new HttpsError("already-exists", "Idempotency key is already in use.");
      }
      return {settlementId, alreadyPosted: true};
    }

    const repMovementRef = firestore.doc(
      businessPath(companyId, "cash_movements", `${settlementId}_rep_out`),
    );
    const companyMovementRef = firestore.doc(
      businessPath(companyId, "cash_movements", `${settlementId}_company_in`),
    );
    if (
      (await transaction.get(repMovementRef)).exists ||
      (await transaction.get(companyMovementRef)).exists
    ) {
      throw new HttpsError("data-loss", "Settlement movement pair is incomplete.");
    }
    const repBalance = await readCashBalance(
      transaction,
      firestore,
      companyId,
      "rep_cash",
      salesRepId,
    );
    const companyBalance = await readCashBalance(
      transaction,
      firestore,
      companyId,
      "company_cash",
      "",
    );
    const repAfter = roundMoney(repBalance.amount - amount);
    if (repAfter < 0) {
      throw new HttpsError("failed-precondition", "Settlement exceeds available representative cash.");
    }
    const companyAfter = roundMoney(companyBalance.amount + amount);
    const referenceNumber = `SET-${date.toDate().toISOString().slice(0, 10).replace(/-/g, "")}-${idempotencyKey.slice(0, 6).toUpperCase()}`;
    const common = {
      companyId,
      type: "settlement_to_admin",
      movementType: "settlement_to_admin",
      amount,
      referenceId: settlementId,
      referenceNumber,
      sourceCollection: "settlements",
      sourceId: settlementId,
      sourceNumber: referenceNumber,
      settlementId,
      customerId: "",
      customerName: "",
      date,
      movementDate: date,
      notes: optionalString(input.notes),
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      createdAt: FieldValue.serverTimestamp(),
    };
    transaction.set(repMovementRef, {
      ...common,
      id: repMovementRef.id,
      salesRepId,
      salesRepName,
      cashAccount: "rep_cash",
      direction: "out",
      balanceBefore: repBalance.amount,
      balanceAfter: repAfter,
    });
    transaction.set(companyMovementRef, {
      ...common,
      id: companyMovementRef.id,
      salesRepId: "",
      salesRepName,
      cashAccount: "company_cash",
      direction: "in",
      balanceBefore: companyBalance.amount,
      balanceAfter: companyAfter,
    });
    writeCashBalance(
      transaction,
      repBalance,
      repAfter,
      repMovementRef.id,
      companyId,
    );
    writeCashBalance(
      transaction,
      companyBalance,
      companyAfter,
      companyMovementRef.id,
      companyId,
    );
    transaction.set(settlementRef, {
      id: settlementId,
      companyId,
      settlementNumber: referenceNumber,
      status: "posted",
      amount,
      salesRepId,
      salesRepName,
      repMovementId: repMovementRef.id,
      companyMovementId: companyMovementRef.id,
      settlementDate: date,
      notes: optionalString(input.notes),
      idempotencyKey,
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {settlementId, alreadyPosted: false};
  });
}
