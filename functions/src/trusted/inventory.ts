import {FieldValue, Firestore, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  DEFAULT_COMPANY_ID,
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
  roundQuantity,
} from "./common";

interface CreateItemRequest {
  companyId?: unknown;
  idempotencyKey?: unknown;
  name?: unknown;
  code?: unknown;
  description?: unknown;
  unit?: unknown;
  price?: unknown;
  taxRate?: unknown;
  active?: unknown;
  currentStock?: unknown;
  openingStock?: unknown;
  minStock?: unknown;
  trackStock?: unknown;
  costPrice?: unknown;
  barcode?: unknown;
  category?: unknown;
  warehouseId?: unknown;
}

interface ValidatedItem {
  name: string;
  code: string;
  description: string;
  unit: string;
  price: number;
  taxRate: number;
  active: boolean;
  currentStock: number;
  minStock: number;
  trackStock: boolean;
  costPrice: number;
  barcode: string;
  category: string;
  warehouseId: string;
}

export const createItem = onCall(TRUSTED_CALLABLE_OPTIONS, async (request) => {
  const uid = requireCallableUid(request, "createItem");
  const input = record(request.data) as CreateItemRequest;
  const companyId = requiredString(input.companyId, "companyId");
  const key = requiredIdempotencyKey(input.idempotencyKey);
  return createItemTransaction(
    getFirestore(),
    uid,
    companyId,
    key,
    input,
  );
});

export async function createItemTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  idempotencyKey: string,
  input: CreateItemRequest,
): Promise<{itemId: string; alreadyPosted: boolean}> {
  const item = validateItem(input);
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    if (user.role !== "admin" || companyId !== DEFAULT_COMPANY_ID) {
      throw new HttpsError("permission-denied", "Only administrators can create items.");
    }
    const itemId = deterministicId("item", idempotencyKey);
    const itemRef = firestore.doc(`items/${itemId}`);
    const existing = await transaction.get(itemRef);
    if (existing.exists) {
      const data = existing.data() ?? {};
      if (!sameItemRequest(data, user.uid, companyId, idempotencyKey, item)) {
        throw new HttpsError("already-exists", "Idempotency key is already in use.");
      }
      return {itemId, alreadyPosted: true};
    }

    const movementId = `${itemId}_opening_balance`;
    const movementRef = firestore.doc(
      businessPath(companyId, "stock_movements", movementId),
    );
    if (item.currentStock > 0 && (await transaction.get(movementRef)).exists) {
      throw new HttpsError("data-loss", "Opening movement exists without its item.");
    }

    transaction.set(itemRef, {
      id: itemId,
      companyId,
      idempotencyKey,
      name: item.name,
      code: item.code,
      description: item.description,
      unit: item.unit,
      price: item.price,
      taxRate: item.taxRate,
      active: item.active,
      deleted: false,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      createdBy: user.uid,
      currentStock: item.currentStock,
      openingStock: item.currentStock,
      minStock: item.minStock,
      trackStock: item.trackStock,
      costPrice: item.costPrice,
      barcode: item.barcode || null,
      category: item.category || null,
      warehouseId: item.warehouseId,
      inventoryUpdatedAt: FieldValue.serverTimestamp(),
      ...(item.currentStock > 0 ? {
        lastInventoryReferenceType: "openingBalance",
        lastInventoryReferenceId: itemId,
        lastStockMovementId: movementId,
      } : {}),
    });
    if (item.currentStock > 0) {
      transaction.set(movementRef, {
        id: movementId,
        companyId,
        warehouseId: item.warehouseId,
        itemId,
        itemName: item.name,
        itemCode: item.code,
        movementType: "opening_balance",
        direction: "in",
        quantity: item.currentStock,
        quantityBefore: 0,
        quantityAfter: item.currentStock,
        referenceType: "item",
        referenceId: itemId,
        referenceNumber: item.code,
        movementDate: FieldValue.serverTimestamp(),
        notes: "",
        createdByUid: user.uid,
        createdByName: user.name,
        createdByRole: user.role,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    return {itemId, alreadyPosted: false};
  });
}

function validateItem(input: CreateItemRequest): ValidatedItem {
  const currentStock = roundQuantity(
    finiteNumber(input.currentStock, "currentStock"),
  );
  const openingStock = roundQuantity(
    finiteNumber(input.openingStock, "openingStock"),
  );
  const minStock = roundQuantity(finiteNumber(input.minStock, "minStock"));
  const price = roundMoney(finiteNumber(input.price, "price"));
  const costPrice = roundMoney(finiteNumber(input.costPrice, "costPrice"));
  const taxRate = roundMoney(finiteNumber(input.taxRate, "taxRate"));
  const trackStock = input.trackStock === true;
  if (
    currentStock < 0 || openingStock < 0 || minStock < 0 ||
    price < 0 || costPrice < 0 || taxRate < 0 || taxRate > 100 ||
    Math.abs(currentStock - openingStock) > 0.0005 ||
    (!trackStock && currentStock !== 0)
  ) {
    throw new HttpsError("invalid-argument", "Item values are invalid.");
  }
  return {
    name: requiredString(input.name, "name"),
    code: requiredString(input.code, "code"),
    description: requiredString(input.description, "description"),
    unit: requiredString(input.unit, "unit"),
    price,
    taxRate,
    active: input.active !== false,
    currentStock,
    minStock,
    trackStock,
    costPrice,
    barcode: optionalString(input.barcode),
    category: optionalString(input.category),
    warehouseId: optionalString(input.warehouseId) || "default_warehouse",
  };
}

function sameItemRequest(
  data: Record<string, unknown>,
  uid: string,
  companyId: string,
  idempotencyKey: string,
  item: ValidatedItem,
): boolean {
  return data.createdBy === uid &&
    data.companyId === companyId &&
    data.idempotencyKey === idempotencyKey &&
    data.name === item.name &&
    data.code === item.code &&
    data.description === item.description &&
    data.unit === item.unit &&
    roundMoney(numberFrom(data, "price")) === item.price &&
    roundMoney(numberFrom(data, "taxRate")) === item.taxRate &&
    data.active === item.active &&
    roundQuantity(numberFrom(data, "currentStock")) === item.currentStock &&
    roundQuantity(numberFrom(data, "openingStock")) === item.currentStock &&
    roundQuantity(numberFrom(data, "minStock")) === item.minStock &&
    data.trackStock === item.trackStock &&
    roundMoney(numberFrom(data, "costPrice")) === item.costPrice &&
    optionalString(data.barcode) === item.barcode &&
    optionalString(data.category) === item.category &&
    data.warehouseId === item.warehouseId;
}
