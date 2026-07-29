import {AuditActions} from "./audit_actions";

export interface EntityAuditConfig {
  entityType: string;
  category: string;
  fields: string[];
  numberFields?: string[];
  labelFields?: string[];
  visible: boolean;
  createAction: string;
  updateAction: string;
  deleteAction: string;
}

const commonActorFields = [
  "createdByUid", "createdByName", "createdByRole", "updatedByUid",
  "updatedByName", "confirmedByUid", "confirmedByName", "approvedByUid",
  "approvedByName", "rejectedByUid", "rejectedByName",
];

export const ENTITY_CONFIGS: Record<string, EntityAuditConfig> = {
  customers: config("customer", "customers", [
    "name", "phone", "email", "address", "taxNumber", "active",
    "openingBalance", "balance", "creditBalance", "notes", ...commonActorFields,
  ], AuditActions.customer.created, AuditActions.customer.updated,
  AuditActions.customer.archived, ["customerNumber"], ["name"]),
  invoices: config("invoice", "sales", [
    "invoiceNumber", "status", "invoiceType", "customerId", "customerName",
    "salesRepId", "salesRepName", "subtotal", "totalDiscount", "totalTax",
    "grandTotal", "paidAmount", "remainingAmount", "paymentType", "notes",
    "operationId", ...commonActorFields,
  ], AuditActions.invoice.created, AuditActions.invoice.updated,
  AuditActions.invoice.deleted, ["invoiceNumber"], ["invoiceNumber"]),
  sales_returns: config("sales_return", "sales", [
    "returnNumber", "invoiceId", "invoiceNumber", "status", "customerId",
    "customerName", "salesRepId", "salesRepName", "subtotal", "totalDiscount",
    "totalTax", "grandTotal", "refundAmount", "creditAmount", "reason",
    "operationId", ...commonActorFields,
  ], AuditActions.salesReturn.created, AuditActions.salesReturn.updated,
  AuditActions.salesReturn.deleted, ["returnNumber"], ["returnNumber"]),
  quotations: config("quotation", "sales", [
    "quotationNumber", "status", "customerId", "customerName", "salesRepId",
    "salesRepName", "subtotal", "totalDiscount", "totalTax", "grandTotal",
    "invoiceId", "notes", "operationId", ...commonActorFields,
  ], AuditActions.quotation.created, AuditActions.quotation.updated,
  AuditActions.quotation.cancelled, ["quotationNumber"], ["quotationNumber"]),
  receipts: config("receipt", "financial", [
    "receiptNumber", "customerId", "customerName", "salesRepId", "salesRepName",
    "amount", "paymentMethod", "allocations", "status", "notes", "operationId",
    ...commonActorFields,
  ], AuditActions.receipt.created, AuditActions.receipt.updated,
  AuditActions.receipt.deleted, ["receiptNumber"], ["receiptNumber"]),
  expenses: config("expense", "financial", [
    "expenseNumber", "status", "amount", "category", "fundingSource",
    "paidByUid", "paidByName", "salesRepId", "salesRepName", "description",
    "notes", "rejectionReason", "reimbursementStatus", "operationId",
    ...commonActorFields,
  ], AuditActions.expense.created, AuditActions.expense.updated,
  AuditActions.expense.deleted, ["expenseNumber"], ["description", "notes"]),
  inventory_transfers: config("inventory_transfer", "inventory", [
    "transferNumber", "status", "direction", "salesRepId", "salesRepName",
    "totalQuantity", "lines", "notes", "cancellationReason", "operationId",
    ...commonActorFields,
  ], AuditActions.transfer.created, AuditActions.transfer.updated,
  AuditActions.transfer.deleted, ["transferNumber"], ["transferNumber"]),
  stock_movements: config("stock_movement", "inventory", [
    "itemId", "itemModel", "itemName", "movementType", "quantity",
    "quantityDelta", "beforeQuantity", "afterQuantity", "warehouseId",
    "salesRepId", "sourceType", "sourceId", "operationId", "reason", "notes",
    ...commonActorFields,
  ], AuditActions.stock.movementPosted, AuditActions.stock.movementPosted,
  AuditActions.data.changed, [], ["itemName", "itemModel"], false),
  rep_inventory_movements: config("rep_inventory_movement", "inventory", [
    "itemId", "itemModel", "itemName", "movementType", "quantity",
    "quantityDelta", "beforeQuantity", "afterQuantity", "salesRepId",
    "salesRepName", "transferId", "sourceId", "operationId", "notes",
    ...commonActorFields,
  ], AuditActions.repInventory.increased, AuditActions.data.changed,
  AuditActions.data.changed, [], ["itemName", "itemModel"], false),
  rep_inventory_balances: config("rep_inventory_balance", "inventory", [
    "itemId", "itemModel", "itemName", "quantity", "salesRepId", "salesRepName",
    "operationId", ...commonActorFields,
  ], AuditActions.data.changed, AuditActions.data.changed,
  AuditActions.data.changed, [], ["itemName"], false),
  customer_transactions: config("customer_transaction", "financial", [
    "customerId", "customerName", "type", "amount", "balanceBefore",
    "balanceAfter", "invoiceId", "receiptId", "returnId", "salesRepId",
    "operationId", "notes", ...commonActorFields,
  ], AuditActions.data.changed, AuditActions.data.changed,
  AuditActions.data.changed, [], ["type"], false),
  cash_movements: config("cash_movement", "financial", [
    "type", "cashAccount", "amount", "balanceBefore", "balanceAfter",
    "salesRepId", "salesRepName", "sourceType", "sourceId", "operationId",
    "notes", ...commonActorFields,
  ], AuditActions.data.changed, AuditActions.data.changed,
  AuditActions.data.changed, [], ["type"], false),
  counters: config("numbering_counter", "settings", [
    "year", "value", "prefix", "nextNumber", "updatedByUid", "operationId",
  ], AuditActions.settings.counterChanged, AuditActions.settings.counterChanged,
  AuditActions.data.changed, [], ["prefix"], false),
  settings: config("settings", "settings", [
    "companySettings", "documentSettings", "inventorySettings", "pdfSettings",
    "permissionSettings", "jofotaraStatusSettings", "schemaVersion",
    "updatedByUid", "updatedByName", "reason", "operationId",
  ], AuditActions.settings.updated, AuditActions.settings.updated,
  AuditActions.data.changed, [], ["updatedByName"]),
  settlements: config("settlement", "financial", [
    "settlementNumber", "status", "amount", "salesRepId", "salesRepName",
    "notes", "reason", "operationId", ...commonActorFields,
  ], AuditActions.settlement.created, AuditActions.settlement.created,
  AuditActions.settlement.cancelled, ["settlementNumber"], ["settlementNumber"]),
  items: config("item", "inventory", [
    "name", "model", "barcode", "salePrice", "purchasePrice", "taxRate",
    "trackStock", "stockQuantity", "minStock", "active", "notes",
    "operationId", ...commonActorFields,
  ], AuditActions.item.created, AuditActions.item.updated,
  AuditActions.item.archived, [], ["name", "model"]),
  users: config("user", "security", [
    "name", "email", "phone", "role", "active", "approvalStatus", "companyId",
    "approvedByUid", "rejectedByUid", "rejectionReason", "updatedByUid",
    "reason",
  ], AuditActions.user.created, AuditActions.user.updated,
  AuditActions.user.deactivated, [], ["name", "email"]),
};

function config(
  entityType: string, category: string, fields: string[],
  createAction: string, updateAction: string, deleteAction: string,
  numberFields: string[] = [], labelFields: string[] = [],
  visible = true,
): EntityAuditConfig {
  return {entityType, category, fields, visible, createAction, updateAction,
    deleteAction, numberFields, labelFields};
}
