import {HttpsError} from "firebase-functions/v2/https";
import {multiplyDecimal, percentageDecimal, sumDecimals} from "./exact_decimal";
import {
  finiteNumber,
  optionalString,
  record,
  roundMoney,
  roundQuantity,
} from "./common";

export interface TrustedInvoiceLine {
  lineId: string;
  lineType: "catalog" | "custom";
  itemId: string | null;
  itemName: string;
  description: string;
  itemCode: string;
  unit: string;
  quantity: number;
  unitPrice: number;
  discount: number;
  taxPercent: number;
  subtotal: number;
  taxAmount: number;
  total: number;
  /** Internal compatibility marker. Never persist this field. */
  lineTypeExplicit: boolean;
}

export interface TrustedInvoiceTotals {
  items: TrustedInvoiceLine[];
  subtotal: number;
  totalDiscount: number;
  totalTax: number;
  grandTotal: number;
}

export function calculateInvoiceTotals(rawLines: unknown): TrustedInvoiceTotals {
  if (!Array.isArray(rawLines) || rawLines.length === 0 || rawLines.length > 100) {
    throw new HttpsError("invalid-argument", "Invoice must contain 1 to 100 lines.");
  }
  const items = rawLines.map((raw, index) => calculateInvoiceLine(raw, index));
  const totals = totalsFromTrustedLines(items);
  if (totals.grandTotal <= 0) {
    throw new HttpsError("invalid-argument", "Invoice grand total must be greater than zero.");
  }
  return totals;
}

export function totalsFromTrustedLines(items: TrustedInvoiceLine[]): TrustedInvoiceTotals {
  return {
    items,
    subtotal: sumDecimals(items.map((item) => item.subtotal)),
    totalDiscount: sumDecimals(items.map((item) => item.discount)),
    totalTax: sumDecimals(items.map((item) => item.taxAmount)),
    grandTotal: sumDecimals(items.map((item) => item.total)),
  };
}

export function calculateInvoiceLine(raw: unknown, index: number): TrustedInvoiceLine {
  const data = record(raw);
  const rawLineType = optionalString(data.lineType);
  if (rawLineType && rawLineType !== "catalog" && rawLineType !== "custom") {
    throw new HttpsError("invalid-argument", `Invoice line ${index + 1} type is invalid.`);
  }
  const rawItemId = optionalString(data.itemId);
  const lineType: "catalog" | "custom" = rawLineType === "catalog" || rawLineType === "custom"
    ? rawLineType
    :
    (rawItemId && !rawItemId.startsWith("manual-") ? "catalog" : "custom");
  const rawQuantity = finiteNumber(data.quantity, `items[${index}].quantity`);
  const rawUnitPrice = finiteNumber(data.unitPrice, `items[${index}].unitPrice`);
  const rawTaxPercent = finiteNumber(data.taxPercent, `items[${index}].taxPercent`);
  const rawDiscount = finiteNumber(data.discount ?? 0, `items[${index}].discount`);
  if (rawQuantity <= 0 || rawUnitPrice < 0 || rawDiscount < 0 ||
    rawTaxPercent < 0 || rawTaxPercent > 100) {
    throw new HttpsError("invalid-argument", `Invoice line ${index + 1} is invalid.`);
  }
  const quantity = roundQuantity(rawQuantity);
  const unitPrice = roundMoney(rawUnitPrice);
  const taxPercent = roundMoney(rawTaxPercent);
  const requestedDiscount = roundMoney(rawDiscount);
  if (quantity <= 0) {
    throw new HttpsError("invalid-argument", `Invoice line ${index + 1} is invalid.`);
  }
  const subtotal = multiplyDecimal(quantity, unitPrice);
  if (requestedDiscount < 0 || requestedDiscount > subtotal) {
    throw new HttpsError("invalid-argument", `Invoice line ${index + 1} discount is invalid.`);
  }
  const taxable = roundMoney(subtotal - requestedDiscount);
  const taxAmount = percentageDecimal(taxable, taxPercent);
  const total = roundMoney(taxable + taxAmount);
  if (total < 0) {
    throw new HttpsError("invalid-argument", `Invoice line ${index + 1} total is invalid.`);
  }
  return {
    lineId: optionalString(data.lineId) || `legacy-line-${index}`,
    lineType,
    itemId: rawItemId || null,
    itemName: optionalString(data.itemName),
    description: optionalString(data.description),
    itemCode: optionalString(data.itemCode),
    unit: optionalString(data.unit),
    quantity,
    unitPrice,
    discount: requestedDiscount,
    taxPercent,
    subtotal,
    taxAmount,
    total,
    lineTypeExplicit: Boolean(rawLineType),
  };
}

export function persistedInvoiceLine(line: TrustedInvoiceLine): Record<string, unknown> {
  return {
    lineId: line.lineId,
    lineType: line.lineType,
    itemId: line.itemId,
    itemName: line.itemName,
    description: line.description,
    itemCode: line.itemCode,
    unit: line.unit,
    quantity: line.quantity,
    unitPrice: line.unitPrice,
    discount: line.discount,
    taxPercent: line.taxPercent,
    subtotal: line.subtotal,
    taxAmount: line.taxAmount,
    total: line.total,
  };
}

export function calculatePayment(
  grandTotal: number,
  hasReceivedPayment: boolean,
  requestedPaidAmount: unknown,
): {paidAmount: number; remainingAmount: number; paymentType: string; paymentStatus: string} {
  const paid = roundMoney(finiteNumber(requestedPaidAmount ?? 0, "paidAmount"));
  if (!hasReceivedPayment) {
    if (paid !== 0) {
      throw new HttpsError("invalid-argument", "Unpaid invoice contains a paid amount.");
    }
    return {
      paidAmount: 0,
      remainingAmount: grandTotal,
      paymentType: "credit",
      paymentStatus: "unpaid",
    };
  }
  if (paid <= 0 || paid > grandTotal) {
    throw new HttpsError("invalid-argument", "Invoice paid amount is invalid.");
  }
  const remaining = roundMoney(grandTotal - paid);
  return {
    paidAmount: paid,
    remainingAmount: remaining,
    paymentType: remaining === 0 ? "cash" : "partial",
    paymentStatus: remaining === 0 ? "paid" : "partiallyPaid",
  };
}
