import {
  DocumentData,
  DocumentReference,
  FieldValue,
  Firestore,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {numberFrom, roundMoney} from "./common";

export type CashAccount = "company_cash" | "rep_cash";

export interface CashBalanceState {
  ref: DocumentReference;
  amount: number;
  account: CashAccount;
  salesRepId: string;
}

export function cashBalanceDocumentId(
  account: CashAccount,
  salesRepId: string,
): string {
  return account === "company_cash" ? "company_cash" : `rep_${salesRepId}`;
}

export async function readCashBalance(
  transaction: Transaction,
  firestore: Firestore,
  companyId: string,
  account: CashAccount,
  salesRepId: string,
): Promise<CashBalanceState> {
  if (account === "rep_cash" && !salesRepId) {
    throw new HttpsError("invalid-argument", "Representative cash requires a representative.");
  }
  const reconciliationLock = await transaction.get(
    firestore.doc(`companies/${companyId}/maintenance_locks/cash_reconciliation`),
  );
  if (reconciliationLock.data()?.active === true) {
    throw new HttpsError(
      "failed-precondition",
      "Cash reconciliation is in progress. Try again after it completes.",
    );
  }
  const id = cashBalanceDocumentId(account, salesRepId);
  const ref = firestore.doc(`companies/${companyId}/cash_balances/${id}`);
  const snapshot = await transaction.get(ref);
  if (snapshot.exists) {
    const data = snapshot.data() ?? {};
    if (data.cashAccount !== account || (data.salesRepId ?? "") !== salesRepId) {
      throw new HttpsError("data-loss", "Cash balance identity is inconsistent.");
    }
    return {ref, amount: roundMoney(numberFrom(data, "amount")), account, salesRepId};
  }

  let query = firestore
    .collection(`companies/${companyId}/cash_movements`)
    .where("cashAccount", "==", account);
  if (account === "rep_cash") query = query.where("salesRepId", "==", salesRepId);
  const existingMovement = await transaction.get(query.limit(1));
  if (!existingMovement.empty) {
    throw new HttpsError(
      "failed-precondition",
      "Cash balance is missing and must be reconciled before posting.",
    );
  }
  return {ref, amount: 0, account, salesRepId};
}

export function writeCashBalance(
  transaction: Transaction,
  state: CashBalanceState,
  nextAmount: number,
  movementId: string,
  companyId: string,
): void {
  transaction.set(state.ref, {
    id: state.ref.id,
    companyId,
    cashAccount: state.account,
    salesRepId: state.salesRepId,
    amount: roundMoney(nextAmount),
    lastMovementId: movementId,
    updatedAt: FieldValue.serverTimestamp(),
  } as DocumentData, {merge: true});
}

export async function applyCashChange(
  transaction: Transaction,
  firestore: Firestore,
  companyId: string,
  account: CashAccount,
  salesRepId: string,
  direction: "in" | "out",
  amount: number,
  movementId: string,
  rejectNegative = true,
): Promise<{before: number; after: number}> {
  const state = await readCashBalance(
    transaction,
    firestore,
    companyId,
    account,
    salesRepId,
  );
  const next = roundMoney(state.amount + (direction === "in" ? amount : -amount));
  if (rejectNegative && next < 0) {
    throw new HttpsError("failed-precondition", "Insufficient cash balance.");
  }
  writeCashBalance(transaction, state, next, movementId, companyId);
  return {before: state.amount, after: next};
}
