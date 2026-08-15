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
} from "./common";
import {applyCashChange} from "./cash_ledger";

export const COMPANY_CASH_OPENING_BALANCE_UID =
  "Ku5x8xXv1BhJQ0yQkVXtYtYOjQn1";
export const COMPANY_CASH_OPENING_BALANCE_EMAIL =
  "osamahesham101@gmail.com";
export const COMPANY_CASH_OPENING_BALANCE_MOVEMENT_ID =
  "company_cash_opening_balance";
export const COMPANY_CASH_OPENING_BALANCE_DATE = Timestamp.fromDate(
  new Date("2026-07-30T00:00:00.000Z"),
);

interface CompanyCashOpeningBalanceRequest {
  companyId?: unknown;
  amount?: unknown;
  note?: unknown;
}

interface CompanyCashOpeningBalanceResult {
  movementId: string;
  balanceAfter: number;
  alreadyPosted: boolean;
}

export const postCompanyCashOpeningBalance = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    const uid = requireCallableUid(request, "postCompanyCashOpeningBalance");
    const tokenEmail = optionalString(request.auth?.token.email).toLowerCase();
    if (
      uid !== COMPANY_CASH_OPENING_BALANCE_UID ||
      tokenEmail !== COMPANY_CASH_OPENING_BALANCE_EMAIL
    ) {
      throw new HttpsError(
        "permission-denied",
        "This migration is restricted to the designated account.",
      );
    }
    const input = record(request.data) as CompanyCashOpeningBalanceRequest;
    const companyId = requiredString(input.companyId, "companyId");
    return postCompanyCashOpeningBalanceTransaction(
      getFirestore(),
      uid,
      companyId,
      input,
    );
  },
);

export async function postCompanyCashOpeningBalanceTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  input: CompanyCashOpeningBalanceRequest,
): Promise<CompanyCashOpeningBalanceResult> {
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(
      transaction,
      firestore,
      uid,
      companyId,
    );
    if (
      user.role !== "admin" ||
      user.uid !== COMPANY_CASH_OPENING_BALANCE_UID ||
      user.email.toLowerCase() !== COMPANY_CASH_OPENING_BALANCE_EMAIL
    ) {
      throw new HttpsError(
        "permission-denied",
        "This migration is restricted to the designated account.",
      );
    }

    const amount = roundMoney(finiteNumber(input.amount, "amount"));
    if (amount <= 0 || amount > 999999999) {
      throw new HttpsError(
        "invalid-argument",
        "Amount must be positive and no greater than 999999999.",
      );
    }
    const note = optionalString(input.note);
    if (note.length > 500) {
      throw new HttpsError(
        "invalid-argument",
        "Note must not exceed 500 characters.",
      );
    }

    const movementRef = firestore.doc(
      businessPath(
        companyId,
        "cash_movements",
        COMPANY_CASH_OPENING_BALANCE_MOVEMENT_ID,
      ),
    );
    const byMovementType = await transaction.get(
      firestore
        .collection(`companies/${companyId}/cash_movements`)
        .where("cashAccount", "==", "company_cash")
        .where("movementType", "==", "opening_balance")
        .limit(2),
    );
    const byType = await transaction.get(
      firestore
        .collection(`companies/${companyId}/cash_movements`)
        .where("cashAccount", "==", "company_cash")
        .where("type", "==", "opening_balance")
        .limit(2),
    );
    const movementSnapshot = await transaction.get(movementRef);
    const openingMovementIds = new Set([
      ...byMovementType.docs.map((document) => document.id),
      ...byType.docs.map((document) => document.id),
    ]);

    if (openingMovementIds.size > 1) {
      throw new HttpsError(
        "failed-precondition",
        "More than one company cash opening balance already exists.",
      );
    }
    const existingId = [...openingMovementIds][0];
    if (existingId && existingId !== movementRef.id) {
      throw new HttpsError(
        "already-exists",
        "Company cash already has an opening balance.",
      );
    }
    if (movementSnapshot.exists) {
      const existing = movementSnapshot.data() ?? {};
      if (!openingMovementIds.has(movementRef.id)) {
        throw new HttpsError(
          "data-loss",
          "The company cash opening balance record is inconsistent.",
        );
      }
      if (
        existing.companyId === companyId &&
        existing.cashAccount === "company_cash" &&
        existing.movementType === "opening_balance" &&
        existing.type === "opening_balance" &&
        existing.direction === "in" &&
        roundMoney(numberFrom(existing, "amount")) === amount &&
        optionalString(existing.notes) === note &&
        sameTimestamp(existing.effectiveDate, COMPANY_CASH_OPENING_BALANCE_DATE)
      ) {
        return {
          movementId: movementRef.id,
          balanceAfter: roundMoney(numberFrom(existing, "balanceAfter")),
          alreadyPosted: true,
        };
      }
      throw new HttpsError(
        "already-exists",
        "Company cash already has a different opening balance.",
      );
    }
    if (existingId) {
      throw new HttpsError(
        "already-exists",
        "Company cash already has an opening balance.",
      );
    }

    const cashChange = await applyCashChange(
      transaction,
      firestore,
      companyId,
      "company_cash",
      "",
      "in",
      amount,
      movementRef.id,
    );
    const referenceNumber = "OPENING-20260730";
    transaction.create(movementRef, {
      id: movementRef.id,
      companyId,
      movementType: "opening_balance",
      type: "opening_balance",
      direction: "in",
      amount,
      cashAccount: "company_cash",
      balanceBefore: cashChange.before,
      balanceAfter: cashChange.after,
      effectiveDate: COMPANY_CASH_OPENING_BALANCE_DATE,
      date: COMPANY_CASH_OPENING_BALANCE_DATE,
      movementDate: COMPANY_CASH_OPENING_BALANCE_DATE,
      referenceId: movementRef.id,
      referenceNumber,
      sourceCollection: "cash_movements",
      sourceId: movementRef.id,
      sourceNumber: referenceNumber,
      operationId: movementRef.id,
      customerId: "",
      customerName: "",
      salesRepId: "",
      salesRepName: "",
      notes: note,
      immutable: true,
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {
      movementId: movementRef.id,
      balanceAfter: cashChange.after,
      alreadyPosted: false,
    };
  });
}

function sameTimestamp(value: unknown, expected: Timestamp): boolean {
  return value instanceof Timestamp && value.isEqual(expected);
}
