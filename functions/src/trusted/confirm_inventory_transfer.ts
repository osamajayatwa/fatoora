import {
  DocumentData,
  DocumentReference,
  FieldValue,
  Firestore,
  getFirestore,
} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  TRUSTED_CALLABLE_OPTIONS,
  businessPath,
  optionalString,
  record,
  requireCallableUid,
  requireTrustedUser,
  requiredString,
  roundQuantity,
} from "./common";

interface InventoryTransferRequest {
  companyId?: unknown;
  transferId?: unknown;
}

interface TransferLine {
  itemId: string;
  quantity: number;
}

interface PreparedLine extends TransferLine {
  item: DocumentData;
  itemRef: DocumentReference;
  balance?: DocumentData;
  balanceRef: DocumentReference;
  companyMovementRef: DocumentReference;
  repMovementRef: DocumentReference;
}

export const confirmInventoryTransfer = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    const uid = requireCallableUid(request, "confirmInventoryTransfer");
    const input = record(request.data) as InventoryTransferRequest;
    const companyId = requiredString(input.companyId, "companyId");
    const transferId = requiredDocumentId(input.transferId, "transferId");
    return confirmInventoryTransferTransaction(
      getFirestore(),
      uid,
      companyId,
      transferId,
    );
  },
);

export async function confirmInventoryTransferTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  transferId: string,
): Promise<{transferId: string; alreadyPosted: boolean}> {
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    if (user.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only administrators can confirm inventory transfers.",
      );
    }

    const transferRef = firestore.doc(
      businessPath(companyId, "inventory_transfers", transferId),
    );
    const transferSnapshot = await transaction.get(transferRef);
    if (!transferSnapshot.exists) {
      throw new HttpsError("not-found", "Inventory transfer was not found.");
    }
    const transfer = transferSnapshot.data() ?? {};
    if (transfer.companyId !== companyId || transfer.id !== transferId) {
      failPrecondition(
        "invalid-transfer",
        "Inventory transfer identity is invalid.",
      );
    }
    if (transfer.status === "confirmed") {
      return {transferId, alreadyPosted: true};
    }
    if (transfer.status !== "draft") {
      failPrecondition(
        "not-editable",
        "Inventory transfer is not an editable draft.",
      );
    }

    const transferType = transfer.type;
    if (transferType !== "warehouseToRep" && transferType !== "repToWarehouse") {
      failPrecondition("invalid-transfer", "Inventory transfer type is invalid.");
    }
    const transferNumber = requiredString(
      transfer.transferNumber,
      "transferNumber",
    );
    const salesRepId = requiredDocumentId(transfer.salesRepId, "salesRepId");
    const rawLines = transfer.lines;
    if (!Array.isArray(rawLines) || rawLines.length === 0 || rawLines.length > 100) {
      failPrecondition(
        "invalid-transfer",
        "Inventory transfer lines are invalid.",
      );
    }
    const lines = validateLines(rawLines);

    const repSnapshot = await transaction.get(firestore.doc(`users/${salesRepId}`));
    if (!repSnapshot.exists) {
      failPrecondition(
        "invalid-representative",
        "Sales representative was not found.",
      );
    }
    const rep = repSnapshot.data() ?? {};
    if (rep.role !== "sales_rep" || rep.companyId !== companyId) {
      failPrecondition(
        "invalid-representative",
        "Sales representative is invalid.",
      );
    }
    if (rep.active !== true || rep.approvalStatus !== "approved") {
      failPrecondition(
        "inactive-representative",
        "Sales representative is not active and approved.",
      );
    }
    const salesRepName = optionalString(rep.name) || optionalString(rep.email);
    if (!salesRepName) {
      failPrecondition(
        "invalid-representative",
        "Sales representative name is invalid.",
      );
    }

    const preparedLines: PreparedLine[] = [];
    for (const line of lines) {
      const balanceId = `${salesRepId}_${line.itemId}`;
      const companyMovementId = `${transferId}_${line.itemId}_warehouse`;
      const repMovementId = `${transferId}_${salesRepId}_${line.itemId}`;
      const itemRef = firestore.doc(`items/${line.itemId}`);
      const balanceRef = firestore.doc(
        businessPath(companyId, "rep_inventory_balances", balanceId),
      );
      const companyMovementRef = firestore.doc(
        businessPath(companyId, "stock_movements", companyMovementId),
      );
      const repMovementRef = firestore.doc(
        businessPath(companyId, "rep_inventory_movements", repMovementId),
      );
      const [
        itemSnapshot,
        balanceSnapshot,
        companyMovementSnapshot,
        repMovementSnapshot,
      ] = await transaction.getAll(
        itemRef,
        balanceRef,
        companyMovementRef,
        repMovementRef,
      );
      if (!itemSnapshot.exists) {
        throw new HttpsError("not-found", `Inventory item ${line.itemId} was not found.`);
      }
      if (companyMovementSnapshot.exists || repMovementSnapshot.exists) {
        failPrecondition(
          "partial-posting",
          "Inventory transfer has existing posting records.",
        );
      }
      preparedLines.push({
        ...line,
        item: itemSnapshot.data() ?? {},
        itemRef,
        balance: balanceSnapshot.data(),
        balanceRef,
        companyMovementRef,
        repMovementRef,
      });
    }

    const confirmedLines: DocumentData[] = [];
    let totalQuantity = 0;
    for (const line of preparedLines) {
      const item = line.item;
      if (
        item.id !== line.itemId ||
        item.deleted === true ||
        item.active !== true ||
        item.trackStock !== true
      ) {
        failPrecondition(
          "untracked-item",
          `Inventory item ${line.itemId} is not eligible for stock transfers.`,
        );
      }
      const itemName = requiredString(item.name, "item.name");
      const itemCode = requiredString(item.code, "item.code");
      const itemUnit = requiredString(item.unit, "item.unit");
      const warehouseBefore = inventoryBalance(item, "currentStock");
      const repBefore = line.balance == null
        ? 0
        : inventoryBalance(line.balance, "quantity");
      if (line.balance != null && (
        line.balance.companyId !== companyId ||
        line.balance.salesRepId !== salesRepId ||
        line.balance.itemId !== line.itemId
      )) {
        failPrecondition(
          "invalid-inventory-data",
          `Representative balance for ${line.itemId} is invalid.`,
        );
      }

      let warehouseAfter: number;
      let repAfter: number;
      if (transferType === "warehouseToRep") {
        if (warehouseBefore + 0.0005 < line.quantity) {
          failPrecondition(
            "insufficient-warehouse-stock",
            `Insufficient warehouse stock for ${line.itemId}.`,
          );
        }
        warehouseAfter = roundQuantity(warehouseBefore - line.quantity);
        repAfter = roundQuantity(repBefore + line.quantity);
      } else {
        if (repBefore + 0.0005 < line.quantity) {
          failPrecondition(
            "insufficient-rep-stock",
            `Insufficient representative stock for ${line.itemId}.`,
          );
        }
        warehouseAfter = roundQuantity(warehouseBefore + line.quantity);
        repAfter = roundQuantity(repBefore - line.quantity);
      }

      const companyMovementId = line.companyMovementRef.id;
      const repMovementId = line.repMovementRef.id;
      transaction.update(line.itemRef, {
        currentStock: warehouseAfter,
        inventoryUpdatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        lastInventoryReferenceType: "inventoryTransfer",
        lastInventoryReferenceId: transferId,
        lastStockMovementId: companyMovementId,
      });
      transaction.set(line.balanceRef, {
        id: line.balanceRef.id,
        companyId,
        salesRepId,
        itemId: line.itemId,
        quantity: repAfter,
        modelSnapshot: itemCode,
        itemNameSnapshot: itemName,
        unitSnapshot: itemUnit,
        createdAt: line.balance?.createdAt ?? FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        lastMovementId: repMovementId,
        lastReferenceType: "inventoryTransfer",
        lastReferenceId: transferId,
      });
      transaction.set(line.companyMovementRef, {
        id: companyMovementId,
        companyId,
        warehouseId: optionalString(item.warehouseId) || "default_warehouse",
        itemId: line.itemId,
        itemName,
        itemCode,
        movementType: "inventory_transfer",
        direction: transferType === "warehouseToRep" ? "out" : "in",
        quantity: line.quantity,
        quantityBefore: warehouseBefore,
        quantityAfter: warehouseAfter,
        referenceType: "inventory_transfer",
        referenceId: transferId,
        referenceNumber: transferNumber,
        movementDate: FieldValue.serverTimestamp(),
        notes: optionalString(transfer.notes),
        createdByUid: user.uid,
        createdByName: user.name,
        createdByRole: user.role,
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.set(line.repMovementRef, {
        id: repMovementId,
        companyId,
        salesRepId,
        salesRepNameSnapshot: salesRepName,
        itemId: line.itemId,
        modelSnapshot: itemCode,
        itemNameSnapshot: itemName,
        unitSnapshot: itemUnit,
        direction: transferType === "warehouseToRep" ? "in" : "out",
        quantity: line.quantity,
        quantityBefore: repBefore,
        quantityAfter: repAfter,
        reason: transferType === "warehouseToRep"
          ? "warehouseDelivery"
          : "warehouseReturn",
        referenceType: "inventoryTransfer",
        referenceId: transferId,
        referenceNumber: transferNumber,
        transferType,
        createdByUid: user.uid,
        createdByName: user.name,
        createdAt: FieldValue.serverTimestamp(),
      });
      confirmedLines.push({
        itemId: line.itemId,
        modelSnapshot: itemCode,
        itemNameSnapshot: itemName,
        unitSnapshot: itemUnit,
        quantity: line.quantity,
        warehouseQuantityBefore: warehouseBefore,
        warehouseQuantityAfter: warehouseAfter,
        repQuantityBefore: repBefore,
        repQuantityAfter: repAfter,
        companyMovementId,
        repMovementId,
      });
      totalQuantity = roundQuantity(totalQuantity + line.quantity);
    }

    transaction.update(transferRef, {
      status: "confirmed",
      salesRepNameSnapshot: salesRepName,
      lines: confirmedLines,
      totalQuantity,
      confirmedByUid: user.uid,
      confirmedByName: user.name,
      confirmedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      effectsVersion: 1,
    });
    return {transferId, alreadyPosted: false};
  });
}

function validateLines(rawLines: unknown[]): TransferLine[] {
  const itemIds = new Set<string>();
  return rawLines.map((value, index) => {
    const data = record(value);
    const itemId = requiredDocumentId(data.itemId, `lines[${index}].itemId`);
    if (!itemIds.add(itemId)) {
      throw new HttpsError(
        "invalid-argument",
        "Inventory transfer contains a duplicate item.",
        {reason: "duplicate-item"},
      );
    }
    if (typeof data.quantity !== "number" || !Number.isFinite(data.quantity)) {
      throw new HttpsError(
        "invalid-argument",
        `lines[${index}].quantity is invalid.`,
        {reason: "invalid-quantity"},
      );
    }
    const quantity = roundQuantity(data.quantity);
    if (quantity <= 0) {
      throw new HttpsError(
        "invalid-argument",
        `lines[${index}].quantity must be positive.`,
        {reason: "invalid-quantity"},
      );
    }
    return {itemId, quantity};
  });
}

function inventoryBalance(data: DocumentData, field: string): number {
  const value = data[field];
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    failPrecondition(
      "invalid-inventory-data",
      `${field} contains an invalid inventory balance.`,
    );
  }
  return roundQuantity(value);
}

function requiredDocumentId(value: unknown, field: string): string {
  const id = requiredString(value, field);
  if (id.includes("/") || id.length > 1500) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return id;
}

function failPrecondition(reason: string, message: string): never {
  throw new HttpsError("failed-precondition", message, {reason});
}
