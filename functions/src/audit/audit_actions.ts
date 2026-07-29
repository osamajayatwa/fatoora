export const AuditActions = {
  user: {
    created: "user.created", updated: "user.updated", approved: "user.approved",
    rejected: "user.rejected", activated: "user.activated",
    deactivated: "user.deactivated", roleChanged: "user.role_changed",
    permissionsChanged: "user.permissions_changed",
  },
  customer: {
    created: "customer.created", updated: "customer.updated",
    archived: "customer.archived",
    openingBalanceCreated: "customer.opening_balance_created",
    openingBalanceAdjusted: "customer.opening_balance_adjusted",
    balanceCorrected: "customer.balance_corrected",
  },
  item: {
    created: "item.created", updated: "item.updated", archived: "item.archived",
  },
  stock: {
    adjusted: "stock.adjusted", movementPosted: "stock.movement_posted",
    trackingEnabled: "stock.tracking_enabled",
    trackingDisabled: "stock.tracking_disabled",
  },
  transfer: {
    created: "inventory_transfer.created", updated: "inventory_transfer.updated",
    confirmed: "inventory_transfer.confirmed",
    cancelled: "inventory_transfer.cancelled",
    deleted: "inventory_transfer.deleted",
  },
  repInventory: {
    increased: "rep_inventory.increased",
    decreased: "rep_inventory.decreased",
    returned: "rep_inventory.returned",
  },
  quotation: {
    created: "quotation.created", updated: "quotation.updated",
    cancelled: "quotation.cancelled",
    converted: "quotation.converted_to_invoice",
  },
  invoice: {
    created: "invoice.created", updated: "invoice.updated",
    confirmed: "invoice.confirmed", cancelled: "invoice.cancelled",
    deleted: "invoice.deleted",
  },
  salesReturn: {
    created: "sales_return.created", updated: "sales_return.updated",
    confirmed: "sales_return.confirmed", cancelled: "sales_return.cancelled",
    deleted: "sales_return.deleted",
  },
  receipt: {
    created: "receipt.created", updated: "receipt.updated",
    cancelled: "receipt.cancelled", deleted: "receipt.deleted",
    allocated: "receipt.allocated",
  },
  expense: {
    created: "expense.created", updated: "expense.updated",
    submitted: "expense.submitted", approved: "expense.approved",
    rejected: "expense.rejected", cancelled: "expense.cancelled",
    deleted: "expense.deleted",
  },
  settlement: {
    created: "settlement.created", confirmed: "settlement.confirmed",
    cancelled: "settlement.cancelled",
  },
  settings: {
    updated: "settings.updated", prefixChanged: "document_prefix.changed",
    counterChanged: "numbering_counter.changed",
    profileUpdated: "company_profile.updated",
  },
  data: {changed: "data.changed"},
} as const;
