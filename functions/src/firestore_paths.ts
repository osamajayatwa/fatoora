export function invoiceDocumentPath(companyId: string, invoiceId: string): string {
  return `companies/${companyId}/invoices/${invoiceId}`;
}
