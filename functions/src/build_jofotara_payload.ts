import { InvoiceModel } from "./jofotara_types";

export function buildJofotaraPayload(
  invoice: InvoiceModel,
): string | Record<string, unknown> {
  // TODO: OSAMA MAP THE OFFICIAL XML/UBL PAYLOAD HERE
  // TODO: OSAMA Confirm whether JoFotara expects XML, UBL, JSON, Base64, QR data, or another official format.
  // TODO: OSAMA Add only the official fields after receiving the final integration guide.
  return {
    placeholder: true,
    invoiceId: invoice.id,
    companyId: invoice.companyId,
    invoiceNumber: invoice.invoiceNumber,
    totals: {
      subtotal: invoice.subtotal,
      totalDiscount: invoice.totalDiscount,
      totalTax: invoice.totalTax,
      grandTotal: invoice.grandTotal,
    },
    // TODO: OSAMA Replace this placeholder object with the official JoFotara payload.
  };
}
