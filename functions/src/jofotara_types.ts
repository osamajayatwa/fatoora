import { Timestamp } from "firebase-admin/firestore";

export type InvoiceType = "regular" | "electronic";
export type InvoiceStatus =
  | "draft"
  | "pendingSubmit"
  | "accepted"
  | "rejected"
  | "cancelled";

export interface InvoiceCustomerSnapshot {
  id: string;
  name: string;
  phone: string;
  address: string;
  taxNumber: string;
  nationalNumber: string;
  city: string;
}

export interface InvoiceItemSnapshot {
  lineId: string;
  lineType: "catalog" | "custom";
  itemId?: string | null;
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
}

export interface JoFotaraGovernmentResponse {
  governmentInvoiceId: string;
  uuid: string;
  qrCode: string;
  submittedAt: Timestamp;
  acceptedAt?: Timestamp;
  joFotaraStatus: string;
  joFotaraErrorCode: string;
  joFotaraErrorMessage: string;
  rawResponse: Record<string, unknown>;
}

export interface InvoiceModel {
  id: string;
  companyId: string;
  invoiceNumber: string;
  invoiceType: InvoiceType;
  invoiceStatus: InvoiceStatus;
  invoiceDate: Timestamp;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  createdByUid: string;
  createdByName: string;
  customerId: string;
  customerSnapshot?: InvoiceCustomerSnapshot;
  items: InvoiceItemSnapshot[];
  subtotal: number;
  totalDiscount: number;
  totalTax: number;
  grandTotal: number;
  notes: string;
  paymentMethod: string;
  isLocked: boolean;
  searchKeywords: string[];
  customerNameLower: string;
  itemNamesLower: string[];
  invoiceNumberLower: string;
  dateString: string;
  government?: JoFotaraGovernmentResponse;
}
