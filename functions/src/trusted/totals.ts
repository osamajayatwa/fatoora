import {HttpsError} from "firebase-functions/v2/https";
import {
  finiteNumber,
  optionalString,
  record,
  roundMoney,
  roundQuantity,
} from "./common";

export interface TrustedInvoiceLine {
  itemId: string;
  itemName: string;
  itemCode: string;
  unit: string;
  quantity: number;
  unitPrice: number;
  discount: number;
  taxPercent: number;
  subtotal: number;
  taxAmount: number;
  total: number;
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
  return {
    items,
    subtotal: roundMoney(items.reduce((sum, item) => sum + item.subtotal, 0)),
    totalDiscount: roundMoney(items.reduce((sum, item) => sum + item.discount, 0)),
    totalTax: roundMoney(items.reduce((sum, item) => sum + item.taxAmount, 0)),
    grandTotal: roundMoney(items.reduce((sum, item) => sum + item.total, 0)),
  };
}

export function calculateInvoiceLine(raw: unknown, index: number): TrustedInvoiceLine {
  const data = record(raw);
  const quantity = roundQuantity(finiteNumber(data.quantity, `items[${index}].quantity`));
  const unitPrice = roundMoney(finiteNumber(data.unitPrice, `items[${index}].unitPrice`));
  const taxPercent = roundMoney(finiteNumber(data.taxPercent, `items[${index}].taxPercent`));
  const requestedDiscount = roundMoney(
    finiteNumber(data.discount ?? 0, `items[${index}].discount`),
  );
  if (quantity <= 0 || unitPrice <= 0 || taxPercent < 0 || taxPercent > 100) {
    throw new HttpsError("invalid-argument", `Invoice line ${index + 1} is invalid.`);
  }
  const subtotal = roundMoney(quantity * unitPrice);
  if (requestedDiscount < 0 || requestedDiscount > subtotal) {
    throw new HttpsError("invalid-argument", `Invoice line ${index + 1} discount is invalid.`);
  }
  const taxable = roundMoney(subtotal - requestedDiscount);
  const taxAmount = roundMoney(taxable * taxPercent / 100);
  return {
    itemId: optionalString(data.itemId),
    itemName: optionalString(data.itemName),
    itemCode: optionalString(data.itemCode),
    unit: optionalString(data.unit),
    quantity,
    unitPrice,
    discount: requestedDiscount,
    taxPercent,
    subtotal,
    taxAmount,
    total: roundMoney(taxable + taxAmount),
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
