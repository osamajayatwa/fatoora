import {DocumentSnapshot, getFirestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {REGION, buildSearchKeywords} from "./common";

export const projectStockMovementSearch = onDocumentWritten(
  {
    document: "companies/{companyId}/stock_movements/{movementId}",
    region: REGION,
    retry: true,
  },
  async (event) => projectSearchFields(event.data?.after, [
    "itemName",
    "itemCode",
    "referenceNumber",
    "sourceNumber",
  ]),
);

export const projectRepInventoryMovementSearch = onDocumentWritten(
  {
    document: "companies/{companyId}/rep_inventory_movements/{movementId}",
    region: REGION,
    retry: true,
  },
  async (event) => projectSearchFields(event.data?.after, [
    "itemNameSnapshot",
    "modelSnapshot",
    "transferNumber",
    "salesRepNameSnapshot",
  ]),
);

export const projectSalesReturnSearch = onDocumentWritten(
  {
    document: "companies/{companyId}/sales_returns/{returnId}",
    region: REGION,
    retry: true,
  },
  async (event) => {
    const snapshot = event.data?.after;
    const data = snapshot?.data() ?? {};
    const customer = typeof data.customerSnapshot === "object" &&
      data.customerSnapshot !== null ?
      data.customerSnapshot as Record<string, unknown> : {};
    await projectSearchFields(snapshot, [
      "returnNumber",
      "originalInvoiceNumber",
      "salesRepName",
    ], [customer.name]);
  },
);

export const projectInventoryTransferSearch = onDocumentWritten(
  {
    document: "companies/{companyId}/inventory_transfers/{transferId}",
    region: REGION,
    retry: true,
  },
  async (event) => {
    const snapshot = event.data?.after;
    if (!snapshot?.exists) return;
    const data = snapshot.data() ?? {};
    const lineValues = Array.isArray(data.lines) ? data.lines.flatMap((line) => {
      if (typeof line !== "object" || line === null) return [];
      const record = line as Record<string, unknown>;
      return [record.modelSnapshot, record.itemNameSnapshot];
    }) : [];
    await projectSearchFields(snapshot, [
      "transferNumber",
      "salesRepNameSnapshot",
    ], lineValues);
  },
);

export const projectItemReportingFields = onDocumentWritten(
  {
    document: "items/{itemId}",
    region: REGION,
    retry: true,
  },
  async (event) => {
    const snapshot = event.data?.after;
    if (!snapshot?.exists) return;
    const data = snapshot.data() ?? {};
    const stock = finiteNumber(data.currentStock);
    const minimum = finiteNumber(data.minStock);
    const cost = finiteNumber(data.costPrice);
    const trackStock = data.trackStock !== false;
    const stockStatus = !trackStock
      ? "untracked"
      : stock <= 0
        ? "out"
        : stock <= minimum
          ? "low"
          : "ok";
    const inventoryValue = Math.round(stock * cost * 1000) / 1000;
    const nameLower = String(data.name ?? "").trim().toLowerCase();
    const searchKeywords = buildSearchKeywords([
      data.name,
      data.code,
      data.description,
      data.barcode,
      data.category,
    ]);
    const existingKeywords = Array.isArray(data.searchKeywords) ? data.searchKeywords : [];
    if (data.stockStatus === stockStatus &&
        data.inventoryValue === inventoryValue &&
        data.nameLower === nameLower &&
        arraysEqual(existingKeywords, searchKeywords)) return;
    await getFirestore().doc(snapshot.ref.path).update({
      stockStatus,
      inventoryValue,
      nameLower,
      searchKeywords,
    });
  },
);

async function projectSearchFields(
  snapshot: DocumentSnapshot | undefined,
  fields: string[],
  extraValues: unknown[] = [],
): Promise<void> {
  if (!snapshot?.exists) return;
  const data = snapshot.data() ?? {};
  const expected = buildSearchKeywords([
    ...fields.map((field) => data[field]),
    ...extraValues,
  ]);
  const existing = Array.isArray(data.searchKeywords) ? data.searchKeywords : [];
  if (arraysEqual(existing, expected)) return;
  await getFirestore().doc(snapshot.ref.path).update({searchKeywords: expected});
}

function arraysEqual(left: unknown[], right: unknown[]): boolean {
  return left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

function finiteNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
