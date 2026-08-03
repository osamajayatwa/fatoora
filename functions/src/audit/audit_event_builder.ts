import {createHash} from "node:crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {AuditActions} from "./audit_actions";
import {safeDiff} from "./audit_diff";
import {sanitizeString, safeValue} from "./audit_redaction";
import {
  AUDIT_SCHEMA_VERSION,
  AuditEvent,
  AuditEventLevels,
  AuditResults,
  AuditSeverities,
  AuditSources,
} from "./audit_types";
import {EntityAuditConfig} from "./entity_audit_config";

export interface AuditBuildInput {
  sourceEventId: string;
  eventTime: string;
  authType: string;
  authId?: string;
  companyId: string;
  entityId: string;
  entityPath: string;
  config: EntityAuditConfig;
  before?: Record<string, unknown>;
  after?: Record<string, unknown>;
  actor?: Record<string, unknown>;
}

export function deterministicAuditId(
  sourceEventId: string,
  entityPath: string,
): string {
  return createHash("sha256").update(`${sourceEventId}|${entityPath}`)
    .digest("hex");
}

export function buildAuditEvent(input: AuditBuildInput): AuditEvent | null {
  const current = input.after ?? input.before;
  if (!current) return null;
  const kind = input.before ? (input.after ? "update" : "delete") : "create";
  const changes = safeDiff(input.before, input.after, input.config.fields);
  if (kind === "update" && changes.length === 0) return null;
  if (input.config.entityType === "item" && kind === "update" &&
      changes.every((change) => change.field === "currentStock" ||
        change.field === "stockQuantity")) {
    return null;
  }
  const action = inferAction(input.config, kind, input.before, input.after, changes);
  const actor = actorSnapshot(input, current);
  const entityNumber = firstString(current, input.config.numberFields ?? []);
  const entityLabel = firstString(current, input.config.labelFields ?? []);
  const operationId = operationIdFor(current, input.entityId);
  const eventId = deterministicAuditId(input.sourceEventId, input.entityPath);
  const financialImpact = financialImpactFor(input.config.entityType, current);
  const inventoryImpact = inventoryImpactFor(input.config.entityType, current,
    input.entityId);
  const isManualAdjustment = input.config.entityType === "stock_movement" &&
    current.referenceType === "manual_adjustment";
  const isSettlementPrimary = input.config.entityType === "cash_movement" &&
    Boolean(current.settlementId) && current.cashAccount === "company_cash";
  const isDerived = !input.config.visible && !isManualAdjustment &&
    !isSettlementPrimary;
  const severity = severityFor(action, current);

  return {
    schemaVersion: AUDIT_SCHEMA_VERSION,
    eventId,
    sourceEventId: sanitizeString(input.sourceEventId, 200),
    companyId: sanitizeString(input.companyId, 128),
    occurredAt: Timestamp.fromDate(new Date(input.eventTime)),
    recordedAt: FieldValue.serverTimestamp(),
    eventLevel: isDerived ? AuditEventLevels.dataChange :
      input.config.category === "security" ? AuditEventLevels.security :
        AuditEventLevels.business,
    category: input.config.category,
    action,
    severity,
    result: AuditResults.success,
    displayInTimeline: !isDerived,
    operationId,
    requestId: sanitizeString(stringValue(current.requestId), 200),
    correlationId: sanitizeString(
      stringValue(current.correlationId) || operationId, 200),
    actorType: actor.actorType,
    actorUid: actor.actorUid,
    actorName: actor.actorName,
    actorRole: actor.actorRole,
    authType: sanitizeString(input.authType || "unknown", 40),
    authId: sanitizeString(input.authId ?? "", 200),
    source: sourceFor(input.authType, current),
    platform: sanitizeString(stringValue(current.platform), 40),
    appVersion: sanitizeString(stringValue(current.appVersion), 40),
    entityType: input.config.entityType,
    entityId: sanitizeString(input.entityId, 200),
    entityNumber,
    entityLabel,
    entityPath: sanitizeString(input.entityPath, 500),
    customerId: sanitizeString(stringValue(current.customerId), 200),
    customerNameSnapshot: sanitizeString(
      stringValue(current.customerNameSnapshot) ||
      stringValue(current.customerName), 200),
    salesRepId: sanitizeString(stringValue(current.salesRepId), 200),
    salesRepNameSnapshot: sanitizeString(
      stringValue(current.salesRepNameSnapshot) ||
      stringValue(current.salesRepName), 200),
    summaryKey: `audit_summary_${action.replace(/\./g, "_")}`,
    summaryArgs: safeValue({
      entityNumber, entityLabel, actorName: actor.actorName,
      customerName: stringValue(current.customerName),
      salesRepName: stringValue(current.salesRepName),
    }) as Record<string, unknown>,
    changedFields: changes.map((change) => change.field),
    changes,
    financialImpact,
    inventoryImpact,
    relatedEntities: relatedEntitiesFor(current),
    reason: sanitizeString(
      stringValue(current.reason) ||
      stringValue(current.rejectionReason) ||
      stringValue(current.cancellationReason), 500),
    notes: sanitizeString(
      stringValue(current.notes) || stringValue(current.description), 500),
    metadata: safeValue({
      writeKind: kind,
      sourceCollection: input.entityPath.split("/").at(-2) ?? "",
      diffTruncated: changes.length >= 50,
    }) as Record<string, unknown>,
  };
}

function inferAction(
  config: EntityAuditConfig,
  kind: string,
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
  changes: {field: string}[],
): string {
  if (kind === "create") {
    const createdStatus = stringValue(after?.status ?? after?.invoiceStatus);
    if (config.entityType === "invoice" && createdStatus === "confirmed") {
      return AuditActions.invoice.confirmed;
    }
    if (config.entityType === "sales_return" && createdStatus === "confirmed") {
      return AuditActions.salesReturn.confirmed;
    }
    if (config.entityType === "inventory_transfer" &&
        createdStatus === "confirmed") {
      return AuditActions.transfer.confirmed;
    }
    if (config.entityType === "stock_movement" &&
        after?.referenceType === "manual_adjustment") {
      return AuditActions.stock.adjusted;
    }
    if (config.entityType === "cash_movement" && after?.settlementId &&
        after?.cashAccount === "company_cash") {
      return AuditActions.settlement.confirmed;
    }
    if (config.entityType === "rep_inventory_movement") {
      const movement = stringValue(after?.movementType ?? after?.type)
        .toLowerCase();
      if (movement.includes("return")) return AuditActions.repInventory.returned;
      if (after?.direction === "out" || movement.includes("sale") ||
          movement.includes("decrease")) {
        return AuditActions.repInventory.decreased;
      }
      return AuditActions.repInventory.increased;
    }
    if (config.entityType === "customer" && number(after?.openingBalance) !== 0) {
      return AuditActions.customer.openingBalanceCreated;
    }
    if (config.entityType === "expense" && after?.status === "pending") {
      return AuditActions.expense.submitted;
    }
    return config.createAction;
  }
  if (kind === "delete") return config.deleteAction;
  const from = stringValue(before?.status ?? before?.invoiceStatus ??
    before?.approvalStatus);
  const to = stringValue(after?.status ?? after?.invoiceStatus ??
    after?.approvalStatus);
  switch (config.entityType) {
    case "invoice":
      if (from !== "confirmed" && to === "confirmed") return AuditActions.invoice.confirmed;
      if (to === "cancelled") return AuditActions.invoice.cancelled;
      break;
    case "sales_return":
      if (from !== "confirmed" && to === "confirmed") return AuditActions.salesReturn.confirmed;
      if (to === "cancelled") return AuditActions.salesReturn.cancelled;
      break;
    case "inventory_transfer":
      if (from !== "confirmed" && to === "confirmed") return AuditActions.transfer.confirmed;
      if (to === "cancelled") return AuditActions.transfer.cancelled;
      break;
    case "quotation":
      if (to === "converted" || (!before?.invoiceId && after?.invoiceId)) {
        return AuditActions.quotation.converted;
      }
      if (to === "cancelled") return AuditActions.quotation.cancelled;
      break;
    case "expense":
      if (from !== "approved" && to === "approved") return AuditActions.expense.approved;
      if (from !== "rejected" && to === "rejected") return AuditActions.expense.rejected;
      if (to === "cancelled") return AuditActions.expense.cancelled;
      break;
    case "settlement":
      if (from !== "confirmed" && to === "confirmed") return AuditActions.settlement.confirmed;
      if (to === "cancelled") return AuditActions.settlement.cancelled;
      break;
    case "user":
      if (changes.some((change) => change.field === "role")) return AuditActions.user.roleChanged;
      if (changes.some((change) => change.field === "approvalStatus")) {
        if (to === "approved") return AuditActions.user.approved;
        if (to === "rejected") return AuditActions.user.rejected;
      }
      if (before?.active !== after?.active) {
        return after?.active === true ? AuditActions.user.activated :
          AuditActions.user.deactivated;
      }
      break;
    case "customer":
      if (before?.active !== after?.active && after?.active === false) {
        return AuditActions.customer.archived;
      }
      if (before?.openingBalance !== after?.openingBalance) {
        return AuditActions.customer.openingBalanceAdjusted;
      }
      if (!before?.lastOpeningBalanceTransactionId &&
          after?.lastOpeningBalanceTransactionId) {
        return AuditActions.customer.openingBalanceCreated;
      }
      break;
    case "item":
      if (before?.active !== after?.active && after?.active === false) {
        return AuditActions.item.archived;
      }
      if (before?.trackStock !== after?.trackStock) {
        return after?.trackStock === true ? AuditActions.stock.trackingEnabled :
          AuditActions.stock.trackingDisabled;
      }
      break;
    case "settings":
      if (changes.some((change) => change.field === "documentSettings")) {
        return AuditActions.settings.prefixChanged;
      }
      if (changes.some((change) => change.field === "companySettings")) {
        return AuditActions.settings.profileUpdated;
      }
      if (changes.some((change) => change.field === "permissionSettings")) {
        return AuditActions.user.permissionsChanged;
      }
      break;
  }
  return config.updateAction;
}

function actorSnapshot(
  input: AuditBuildInput,
  current: Record<string, unknown>,
): {actorType: string; actorUid: string; actorName: string; actorRole: string} {
  const actorUid = sanitizeString(input.authId ?? firstString(current, [
    "confirmedByUid", "approvedByUid", "rejectedByUid", "updatedByUid",
    "createdByUid", "paidByUid",
  ]), 200);
  const actorName = firstString(current, [
    "confirmedByName", "approvedByName", "rejectedByName", "updatedByName",
    "createdByName", "paidByName",
  ]) || sanitizeString(stringValue(input.actor?.name), 200);
  const actorRole = sanitizeString(
    stringValue(input.actor?.role) || stringValue(current.createdByRole) ||
    stringValue(current.paidByRole), 80);
  return {
    actorType: actorUid ? "user" :
      input.authType === "system" ? "system" : "service",
    actorUid, actorName, actorRole,
  };
}

function operationIdFor(data: Record<string, unknown>, entityId: string): string {
  return sanitizeString(firstString(data, [
    "operationId", "sourceOperationId", "sourceId", "invoiceId", "returnId",
    "transferId", "receiptId", "expenseId", "settlementId",
    "lastOpeningBalanceTransactionId",
  ]) || entityId, 200);
}

function financialImpactFor(
  entityType: string,
  data: Record<string, unknown>,
): Record<string, unknown> {
  const impact: Record<string, unknown> = {};
  const currency = stringValue(data.currency) || stringValue(data.currencyCode);
  if (currency) impact.currency = sanitizeString(currency, 10);
  if (["invoice", "sales_return"].includes(entityType)) {
    impact.documentTotal = number(data.grandTotal ?? data.total);
  }
  if (entityType === "invoice") {
    impact.receivableDelta = number(data.remainingAmount);
    impact.companyCashDelta = (data.cashAccount === "company_cash" ||
      (!data.cashAccount && data.createdByRole === "admin")) ?
      number(data.paidAmount) : 0;
    impact.repCashDelta = (data.cashAccount === "rep_cash" ||
      (!data.cashAccount && data.createdByRole === "sales_rep")) ?
      number(data.paidAmount) : 0;
  } else if (entityType === "receipt") {
    impact.receivableDelta = -number(data.amount);
    impact.companyCashDelta = data.cashAccount === "company_cash" ?
      number(data.amount) : 0;
    impact.repCashDelta = data.cashAccount === "rep_cash" ?
      number(data.amount) : 0;
  } else if (entityType === "sales_return") {
    impact.receivableDelta = -number(data.receivableReduction ??
      data.creditAmount);
    impact.customerCreditDelta = number(data.creditAmount);
    impact.refundDelta = number(data.refundAmount);
  } else if (entityType === "expense") {
    const amount = number(data.amount);
    if (data.fundingSource === "company_cash") impact.companyCashDelta = -amount;
    if (data.fundingSource === "rep_collected_cash") impact.repCashDelta = -amount;
    if (data.fundingSource === "personal_cash" &&
        data.reimbursementStatus === "payable") {
      impact.reimbursementPayableDelta = amount;
    }
  } else if (entityType === "cash_movement") {
    const delta = data.direction === "out" ? -number(data.amount) : number(data.amount);
    if (data.cashAccount === "company_cash") impact.companyCashDelta = delta;
    if (data.cashAccount === "rep_cash") impact.repCashDelta = delta;
  }
  return safeValue(impact) as Record<string, unknown>;
}

function inventoryImpactFor(
  entityType: string,
  data: Record<string, unknown>,
  entityId: string,
): Record<string, unknown>[] {
  if (entityType === "stock_movement" || entityType === "rep_inventory_movement") {
    return [safeValue({
      itemId: data.itemId, itemModel: data.itemModel,
      itemNameSnapshot: data.itemNameSnapshot ?? data.itemName,
      locationType: entityType === "rep_inventory_movement" ?
        "rep_custody" : "warehouse",
      locationId: data.salesRepId ?? data.warehouseId,
      locationNameSnapshot: data.salesRepName ?? data.warehouseName,
      beforeQuantity: data.beforeQuantity ?? data.quantityBefore,
      quantityDelta: data.quantityDelta ?? data.quantity,
      afterQuantity: data.afterQuantity ?? data.quantityAfter,
      movementType: data.movementType ?? data.type,
      movementId: entityId,
    }) as Record<string, unknown>];
  }
  const lines = Array.isArray(data.lines) ? data.lines :
    Array.isArray(data.items) ? data.items : [];
  if (!["invoice", "sales_return", "inventory_transfer"].includes(entityType)) {
    return [];
  }
  return lines.slice(0, 50).map((line) => {
    const item = line as Record<string, unknown>;
    return safeValue({
      itemId: item.itemId, itemModel: item.itemModel ?? item.model,
      itemNameSnapshot: item.itemNameSnapshot ?? item.itemName ?? item.name,
      locationType: data.salesRepId ? "rep_custody" : "warehouse",
      locationId: data.salesRepId ?? data.warehouseId,
      locationNameSnapshot: data.salesRepName ?? data.warehouseName,
      quantityDelta: item.quantity,
      movementType: entityType,
    }) as Record<string, unknown>;
  });
}

function relatedEntitiesFor(data: Record<string, unknown>): Record<string, unknown>[] {
  const fields: [string, string][] = [
    ["customerId", "customer"], ["invoiceId", "invoice"],
    ["returnId", "sales_return"], ["receiptId", "receipt"],
    ["transferId", "inventory_transfer"], ["salesRepId", "user"],
  ];
  return fields.filter(([field]) => stringValue(data[field]))
    .map(([field, entityType]) => ({
      entityType, entityId: sanitizeString(stringValue(data[field]), 200),
    })).slice(0, 20);
}

function severityFor(action: string, data: Record<string, unknown>): string {
  if (action.endsWith(".deleted") || action === AuditActions.user.roleChanged ||
      action === AuditActions.user.deactivated ||
      action === AuditActions.settings.counterChanged) {
    return AuditSeverities.warning;
  }
  if (data.severity === "critical") return AuditSeverities.critical;
  return AuditSeverities.info;
}

function sourceFor(
  authType: string,
  data: Record<string, unknown>,
): string {
  const source = stringValue(data.source);
  if (source === "web") return AuditSources.web;
  if (source === "android") return AuditSources.android;
  if (authType === "service_account") return AuditSources.cloudFunction;
  if (authType === "system") return AuditSources.system;
  // Firestore auth context identifies the principal, not the client OS.
  // Avoid incorrectly labelling Android writes as web when legacy documents
  // do not yet carry an explicit source snapshot.
  return AuditSources.system;
}

function firstString(data: Record<string, unknown>, fields: string[]): string {
  for (const field of fields) {
    const value = sanitizeString(stringValue(data[field]), 200);
    if (value) return value;
  }
  return "";
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function number(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
