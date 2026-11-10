import {DocumentData, FieldValue, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import type {AccountingDomainWrite, AccountingPostingContext} from "./accounting_posting";
import type {AccountingStockEffect} from "./accounting_controls";
import {accountingDigest, accountingNeed, accountingSame, accountingUnits} from "./accounting_journal";
import {configurationId} from "./accounting_configuration_contract";
import {immutablePositionEvidence, verifyAccountingPosition} from "./accounting_positions";
import {compatibleExactNumber} from "./cash_ledger_exact";
import {sumUnits} from "./exact_decimal";
import {assertAccountingControlContext} from "./accounting_transaction";

export interface ExactStockChange {
  lineId: string; itemId: string; quantityUnits: string; direction: "in" | "out";
  holderType: "warehouse" | "representative"; holderId: string;
  purpose: AccountingStockEffect["purpose"];
}
interface StockPosition {
  path: string; field: AccountingStockEffect["field"]; data: DocumentData; itemId: string; unit: string;
  quantityScale: number; holderType: ExactStockChange["holderType"]; holderId: string; before: bigint; after: bigint; sequence: number;
  movements: {id: string; path: string; data: DocumentData}[];
}
export function exactStockMovementId(source: AccountingPostingContext["source"], change: ExactStockChange): string {
  return `stock_${accountingDigest([source, change.lineId, change.itemId, change.holderType, change.holderId])}`;
}
async function stockPosition(tx: Transaction, db: Firestore, c: AccountingPostingContext, change: ExactStockChange): Promise<StockPosition> {
  const item = (await tx.get(db.doc(`items/${change.itemId}`))).data();
  accountingNeed(item?.id === change.itemId && item.companyId === c.companyId && item.trackStock === true && item.deleted !== true && (item.active === true || change.purpose === "return"), "Item is outside this company or ineligible for physical stock.");
  accountingNeed(typeof item.unit === "string" && item.unit.trim().length > 0 && item.unit.length <= 64, "An explicit stock unit is required.");
  if (change.holderType === "representative") {
    const rep = (await tx.get(db.doc(`users/${change.holderId}`))).data();
    accountingNeed(rep?.companyId === c.companyId && rep.role === "sales_rep" && rep.active === true && rep.approvalStatus === "approved", "Inventory custodian is not approved for this company.");
  } else accountingNeed(item.warehouseId === change.holderId, "Warehouse position identity is invalid.");
  const path = change.holderType === "warehouse" ? `items/${change.itemId}` : `companies/${c.companyId}/rep_inventory_balances/${change.holderId}_${change.itemId}`;
  const ref = db.doc(path), d = change.holderType === "warehouse" ? item : (await tx.get(ref)).data();
  accountingNeed(d, "An exact stock opening/position is required; missing history cannot become zero.");
  const warehouse = change.holderType === "warehouse", scale = warehouse ? d.stockQuantityScale : d.quantityScale;
  accountingNeed(d.companyId === c.companyId && (warehouse ? d.stockBookId : d.bookId) === c.bookId && scale === c.configuration.quantityScale, "Stock position book/precision is inconsistent.");
  if (!warehouse) accountingNeed(d.itemId === change.itemId && d.salesRepId === change.holderId && d.unit === item.unit, "Representative stock dimensions are invalid.");
  const field = warehouse ? "currentStockUnits" as const : "quantityUnits" as const, units = accountingUnits(d[field]);
  const legacy = compatibleExactNumber(units, scale), legacyField = warehouse ? "currentStock" : "quantity";
  accountingNeed(legacy === null ? d[legacyField] === null && d.legacyQuantityCoverage === "not_representable" : d[legacyField] === legacy, "Exact and numeric stock disagree.");
  const sequence = warehouse ? d.stockSequence : d.accountSequence;
  accountingNeed(Number.isSafeInteger(sequence) && sequence >= 1 && sequence < Number.MAX_SAFE_INTEGER, "A proven stock sequence is required.");
  const headId = configurationId(warehouse ? d.lastStockMovementId : d.lastMovementId, "stock head"), collection = warehouse ? "stock_movements" : "rep_inventory_movements";
  const head = await tx.get(db.doc(`companies/${c.companyId}/${collection}/${headId}`));immutablePositionEvidence(head);
  const h = head.data()!, amount = accountingUnits(h.quantityUnits), before = accountingUnits(h.quantityBeforeUnits), after = accountingUnits(h.quantityAfterUnits);
  accountingNeed(h.id === headId && h.companyId === c.companyId && h.bookId === c.bookId && h.itemId === change.itemId && h.unit === item.unit && h.quantityScale === scale &&
    h.holderType === change.holderType && h.holderId === change.holderId && h.accountSequence === sequence && ["in", "out"].includes(h.direction) && (amount > 0n || h.syntheticOpening === true), "Stock head dimensions are invalid.");
  accountingSame(sumUnits([before, h.direction === "in" ? amount : -amount]).toString(), after.toString(), "Stock head balance equation");accountingSame(after.toString(), units.toString(), "Stock head/position quantity");
  const projected = warehouse ? {...d, accountingHeadEventId: d.stockHeadEventId, syntheticOpeningId: d.stockOpeningId} : d;
  const provenCommit = await verifyAccountingPosition(tx, db, c, ref, projected, undefined, warehouse ? "stockUpdatedAt" : "quantityUpdatedAt");
  accountingNeed(head.createTime!.isEqual(provenCommit), "Stock position and its immutable head did not commit together.", "data-loss");
  if (h.accounting) accountingSame(h.accounting.eventId, warehouse ? d.stockHeadEventId : d.accountingHeadEventId, "Stock movement event link");
  return {path, field, data: d, itemId: change.itemId, unit: item.unit, quantityScale: scale, holderType: change.holderType,
    holderId: change.holderId, before: units, after: units, sequence, movements: []};
}

/** Existing stock/custody stores; no cost reads, second inventory ledger or money journal. */
export async function prepareExactInventoryChanges(tx: Transaction, db: Firestore, c: AccountingPostingContext, changes: ExactStockChange[]) {
  assertAccountingControlContext(tx, c.companyId, c.bookId);
  accountingNeed(changes.length > 0 && changes.length <= 200, "Physical changes require 1 to 200 bounded legs.");
  accountingNeed(changes.every(ch => ch.purpose === changes[0].purpose), "One stock plan must have one explicit physical purpose.");
  const sourceTypes: Record<string, string[]> = {transfer: ["inventory_transfers"], sale: ["invoices"], return: ["sales_returns"], receipt: ["stock_adjustments"], count: ["stock_adjustments"]};
  accountingNeed(sourceTypes[changes[0].purpose]?.includes(c.source.type), "Physical purpose does not match its existing business source.");
  const positions = new Map<string, StockPosition>(), identities = new Set<string>(), pending: {id: string; path: string; data: DocumentData}[] = [];
  for (const change of changes) {
    for (const key of ["lineId", "itemId", "holderId"] as const) configurationId(change[key], key);
    accountingNeed(["warehouse", "representative"].includes(change.holderType) && ["in", "out"].includes(change.direction) && ["transfer", "sale", "return", "receipt", "count"].includes(change.purpose), "Unsupported physical stock change.");
    const amount = accountingUnits(change.quantityUnits);accountingNeed(amount > 0n, "Physical quantity must be positive.");
    const key = `${change.itemId}:${change.holderType}:${change.holderId}`, id = exactStockMovementId(c.source, change);
    accountingNeed(!identities.has(id), "Duplicate physical source line/holder.");identities.add(id);
    let position = positions.get(key);if (!position) {position = await stockPosition(tx, db, c, change);positions.set(key, position);}
    const before = position.after, after = sumUnits([before, change.direction === "in" ? amount : -amount]);accountingNeed(after >= 0n, "Insufficient physical stock.");
    accountingNeed(position.sequence + position.movements.length + 1 < Number.MAX_SAFE_INTEGER, "Stock sequence capacity exceeded.");
    const path = `companies/${c.companyId}/${change.holderType === "warehouse" ? "stock_movements" : "rep_inventory_movements"}/${id}`;
    const movement = {id, path, data: {schemaVersion: 1, id, companyId: c.companyId, bookId: c.bookId, itemId: change.itemId,
      unit: position.unit, quantityScale: position.quantityScale, holderType: change.holderType, holderId: change.holderId,
      ...(change.holderType === "representative" ? {salesRepId: change.holderId} : {warehouseId: change.holderId}),
      quantityUnits: amount.toString(), quantityBeforeUnits: before.toString(), quantityAfterUnits: after.toString(),
      quantity: compatibleExactNumber(amount, position.quantityScale), quantityBefore: compatibleExactNumber(before, position.quantityScale), quantityAfter: compatibleExactNumber(after, position.quantityScale),
      direction: change.direction, purpose: change.purpose, lineId: change.lineId, sourceCollection: c.source.type, sourceId: c.source.id,
      accountSequence: position.sequence + position.movements.length + 1, createdByUid: c.actor.uid,
      movementDate: new Timestamp(c.businessTime.seconds, c.businessTime.nanoseconds)}};
    position.after = after;position.movements.push(movement);pending.push(movement);
  }
  // Create preconditions verify absence atomically without 200 redundant reads.
  const groups = [...positions.values()];
  const stockEffects: AccountingStockEffect[] = groups.map(p => ({positionPath: p.path, field: p.field, itemId: p.itemId, unit: p.unit,
    quantityScale: p.quantityScale, holderType: p.holderType, holderId: p.holderId, beforeUnits: p.before.toString(), afterUnits: p.after.toString(),
    movementPaths: p.movements.map(m => m.path), purpose: p.movements[0].data.purpose}));
  return {stockEffects, writes(binding: DocumentData): AccountingDomainWrite[] {
    const writes: AccountingDomainWrite[] = pending.map(m => ({method: "create", path: m.path, data: {...m.data, accounting: binding, createdAt: FieldValue.serverTimestamp()}}));
    for (const p of groups) {
      const last = p.movements.at(-1)!, number = compatibleExactNumber(p.after, p.quantityScale), coverage = number === null ? "not_representable" : "exact";
      if (p.holderType === "warehouse") writes.push({method: "update", path: p.path, data: {companyId: c.companyId, currentStockUnits: p.after.toString(), currentStock: number,
        stockBookId: c.bookId, stockQuantityScale: p.quantityScale, stockSequence: last.data.accountSequence, lastStockMovementId: last.id,
        stockHeadEventId: c.eventId, stockUpdatedAt: FieldValue.serverTimestamp(), legacyQuantityCoverage: coverage, costCoverage: "not_recorded", inventoryValue: null}});
      else writes.push({method: "set", path: p.path, merge: true, data: {id: p.data.id, companyId: c.companyId, bookId: c.bookId, itemId: p.itemId, salesRepId: p.holderId,
        unit: p.unit, quantityScale: p.quantityScale, quantityUnits: p.after.toString(), quantity: number, accountSequence: last.data.accountSequence,
        lastMovementId: last.id, accountingHeadEventId: c.eventId, quantityUpdatedAt: FieldValue.serverTimestamp(), legacyQuantityCoverage: coverage}});
    }
    return writes;
  }};
}
