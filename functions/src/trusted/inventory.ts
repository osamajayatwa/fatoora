import {FieldValue, Firestore, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  DEFAULT_COMPANY_ID,
  TRUSTED_CALLABLE_OPTIONS,
  buildSearchKeywords,
  businessPath,
  deterministicId,
  finiteNumber,
  numberFrom,
  normalizeSearchText,
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

interface AdjustStockRequest {
  companyId?: unknown;
  idempotencyKey?: unknown;
  itemId?: unknown;
  adjustmentType?: unknown;
  quantity?: unknown;
  notes?: unknown;
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

interface ValidatedStockAdjustment {
  itemId: string;
  movementType: string;
  direction: "in" | "out";
  quantity: number;
  notes: string;
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

export const adjustStock = onCall(TRUSTED_CALLABLE_OPTIONS, async (request) => {
  const uid = requireCallableUid(request, "adjustStock");
  const input = record(request.data) as AdjustStockRequest;
  const companyId = requiredString(input.companyId, "companyId");
  const key = requiredIdempotencyKey(input.idempotencyKey);
  return adjustStockTransaction(
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
      inventoryValue: roundMoney(item.currentStock * item.costPrice),
      stockStatus: !item.trackStock
        ? "untracked"
        : item.currentStock <= 0
          ? "out"
          : item.currentStock <= item.minStock
            ? "low"
            : "ok",
      nameLower: normalizeItemSearch(item.name),
      searchKeywords: buildItemSearchKeywords([
        item.name,
        item.code,
        item.description,
        item.barcode,
        item.category,
      ]),
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

export function normalizeItemSearch(value: string): string {
  return normalizeSearchText(value);
}

export function buildItemSearchKeywords(values: string[]): string[] {
  return buildSearchKeywords(values);
}

export async function adjustStockTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  idempotencyKey: string,
  input: AdjustStockRequest,
): Promise<{
  movementId: string;
  quantityAfter: number;
  alreadyPosted: boolean;
}> {
  const adjustment = validateStockAdjustment(input);
  const movementId = deterministicId("stock_adjustment", idempotencyKey);
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    if (user.role !== "admin" || companyId !== DEFAULT_COMPANY_ID) {
      throw new HttpsError(
        "permission-denied",
        "Only administrators can adjust warehouse stock.",
      );
    }

    const movementRef = firestore.doc(
      businessPath(companyId, "stock_movements", movementId),
    );
    const existingMovement = await transaction.get(movementRef);
    if (existingMovement.exists) {
      const data = existingMovement.data() ?? {};
      if (!sameStockAdjustment(
        data,
        user.uid,
        companyId,
        idempotencyKey,
        adjustment,
      )) {
        throw new HttpsError(
          "already-exists",
          "Idempotency key is already in use.",
        );
      }
      return {
        movementId,
        quantityAfter: inventoryBalance(data, "quantityAfter"),
        alreadyPosted: true,
      };
    }

    const itemRef = firestore.doc(`items/${adjustment.itemId}`);
    const itemSnapshot = await transaction.get(itemRef);
    if (!itemSnapshot.exists) {
      throw new HttpsError("not-found", "Inventory item was not found.");
    }
    const item = itemSnapshot.data() ?? {};
    if (
      item.deleted === true ||
      item.trackStock !== true ||
      (optionalString(item.companyId) && item.companyId !== companyId)
    ) {
      failPrecondition(
        "invalid-inventory-item",
        "The item is not available for stock tracking.",
      );
    }

    const before = inventoryBalance(item, "currentStock");
    const after = roundQuantity(
      adjustment.direction === "in" ?
        before + adjustment.quantity :
        before - adjustment.quantity,
    );
    if (after < 0) {
      failPrecondition(
        "insufficient-stock",
        "The stock adjustment exceeds the available quantity.",
      );
    }

    transaction.update(itemRef, {
      currentStock: after,
      inventoryUpdatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      lastInventoryReferenceType: "manualAdjustment",
      lastInventoryReferenceId: movementId,
      lastStockMovementId: movementId,
    });
    transaction.set(movementRef, {
      id: movementId,
      companyId,
      idempotencyKey,
      warehouseId: optionalString(item.warehouseId) || "default_warehouse",
      itemId: adjustment.itemId,
      itemName: optionalString(item.name),
      itemCode: optionalString(item.code),
      movementType: adjustment.movementType,
      direction: adjustment.direction,
      quantity: adjustment.quantity,
      quantityBefore: before,
      quantityAfter: after,
      referenceType: "manual_adjustment",
      referenceId: movementId,
      referenceNumber: "",
      movementDate: FieldValue.serverTimestamp(),
      notes: adjustment.notes,
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {movementId, quantityAfter: after, alreadyPosted: false};
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

function validateStockAdjustment(
  input: AdjustStockRequest,
): ValidatedStockAdjustment {
  const itemId = requiredDocumentId(input.itemId, "itemId");
  const requestedType = requiredString(
    input.adjustmentType,
    "adjustmentType",
  );
  const movementType = requestedType === "increase_stock" ?
    "manual_adjustment_in" :
    requestedType === "decrease_stock" ?
      "manual_adjustment_out" :
      requestedType;
  if (![
    "manual_adjustment_in",
    "manual_adjustment_out",
    "damage",
    "correction",
  ].includes(movementType)) {
    throw new HttpsError("invalid-argument", "adjustmentType is invalid.");
  }
  const quantity = roundQuantity(finiteNumber(input.quantity, "quantity"));
  if (quantity <= 0 || quantity > 999999999) {
    throw new HttpsError("invalid-argument", "quantity must be positive.");
  }
  const notes = requiredString(input.notes, "notes");
  if (notes.length > 500) {
    throw new HttpsError(
      "invalid-argument",
      "notes must not exceed 500 characters.",
    );
  }
  return {
    itemId,
    movementType,
    direction: movementType === "manual_adjustment_out" ||
      movementType === "damage" ? "out" : "in",
    quantity,
    notes,
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

function sameStockAdjustment(
  data: Record<string, unknown>,
  uid: string,
  companyId: string,
  idempotencyKey: string,
  adjustment: ValidatedStockAdjustment,
): boolean {
  return data.createdByUid === uid &&
    data.companyId === companyId &&
    data.idempotencyKey === idempotencyKey &&
    data.itemId === adjustment.itemId &&
    data.movementType === adjustment.movementType &&
    data.direction === adjustment.direction &&
    roundQuantity(numberFrom(data, "quantity")) === adjustment.quantity &&
    optionalString(data.notes) === adjustment.notes;
}

function inventoryBalance(data: Record<string, unknown>, field: string): number {
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
