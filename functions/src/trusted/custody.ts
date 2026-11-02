import {Firestore, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

export async function requireNewCustodyBalance(
  transaction: Transaction, firestore: Firestore, companyId: string, salesRepId: string, itemId: string,
): Promise<void> {
  const history = await transaction.get(firestore.collection(`companies/${companyId}/rep_inventory_movements`)
    .where("salesRepId", "==", salesRepId).where("itemId", "==", itemId).limit(1));
  if (!history.empty) {
    throw new HttpsError("data-loss", "Custody balance is missing despite movement history; reconcile before posting.");
  }
}
