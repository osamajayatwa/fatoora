import {Firestore, Transaction} from "firebase-admin/firestore";
import type {AccountingDomainWrite, AccountingPostingContext} from "./accounting_posting";
import {AccountingJournal, accountingCanonical, accountingNeed, accountingSame, accountingUnits} from "./accounting_journal";
import {configurationId} from "./accounting_configuration_contract";
import {sumUnits} from "./exact_decimal";

export interface AccountingControlEffect {
  kind: "cash" | "receivable" | "customer_credit";
  accountId: string; dimensions: Record<string, string>; positionPath: string; field: string;
  beforeUnits: string; afterUnits: string;
}
export interface AccountingStockEffect {
  positionPath: string; field: "currentStockUnits" | "quantityUnits";
  itemId: string; unit: string; quantityScale: number; holderType: "warehouse" | "representative"; holderId: string;
  beforeUnits: string; afterUnits: string; movementPaths: string[]; purpose: "transfer" | "sale" | "return" | "receipt" | "count";
}

function controlKey(accountId: string, kind: string, dimensions: Record<string, string>): string {
  const keys = kind === "cash" ? ["treasuryAccountId", "holderType", "holderUid"] : ["customerId"];
  const selected = Object.fromEntries(keys.map(k => [k, dimensions[k]]));
  for (const value of Object.values(selected)) configurationId(value, "control dimension");
  return accountingCanonical([accountId, kind, selected]);
}
function add(map: Map<string, bigint>, key: string, delta: bigint): void {map.set(key, sumUnits([map.get(key) ?? 0n, delta]));}
function equalTotals(a: Map<string, bigint>, b: Map<string, bigint>, label: string): void {
  for (const key of new Set([...a.keys(), ...b.keys()])) accountingSame((a.get(key) ?? 0n).toString(), (b.get(key) ?? 0n).toString(), label);
}

/** Independently prove journal deltas against authoritative position/line effects. */
export async function verifyAccountingControls(tx: Transaction, db: Firestore, context: AccountingPostingContext,
  journal: AccountingJournal | null, writes: AccountingDomainWrite[], controls: AccountingControlEffect[], stocks: AccountingStockEffect[]): Promise<void> {
  accountingNeed(controls.length <= 200 && stocks.length <= 200, "Control effect budget exceeded.");
  const byPath = new Map(writes.map(w => [w.path, w])), observed = new Map<string, bigint>(), posted = new Map<string, bigint>(), fields = new Set<string>();
  const relevant = ["cash", "receivable", "customer_credit"];
  for (const line of journal?.lines ?? []) if (relevant.includes(line.account.control)) add(posted, controlKey(line.account.id, line.account.control, line.dimensions as Record<string, string>), BigInt(line.debitUnits) - BigInt(line.creditUnits));
  for (const effect of controls) {
    accountingNeed(relevant.includes(effect.kind), "Unsupported control kind.");configurationId(effect.accountId, "control account");
    const fieldKey = `${effect.positionPath}#${effect.field}`;accountingNeed(!fields.has(fieldKey), "Duplicate control position field.");fields.add(fieldKey);
    const write = byPath.get(effect.positionPath);accountingNeed(write && write.method !== "create", "A control delta requires an existing authoritative position.");
    const before = accountingUnits(effect.beforeUnits), after = accountingUnits(effect.afterUnits), snapshot = await tx.get(db.doc(effect.positionPath));
    accountingSame(snapshot.data()?.[effect.field], before.toString(), "Control position before");accountingSame(write.data[effect.field], after.toString(), "Control position after");
    const role = effect.kind === "receivable" ? "receivables" : effect.kind === "customer_credit" ? "customerCredits" : null;
    if (role) accountingSame(context.configuration.mappings[role], effect.accountId, "Control account mapping");
    else accountingNeed([context.configuration.mappings.companyCash, context.configuration.mappings.representativeCash].includes(effect.accountId), "Treasury effect uses an unconfigured cash control.");
    add(observed, controlKey(effect.accountId, effect.kind, effect.dimensions), effect.kind === "customer_credit" ? before - after : after - before);
  }
  equalTotals(posted, observed, "Journal/subledger control delta");
  const itemTotals = new Map<string, bigint>();
  for (const write of writes.filter(w => w.path.includes(`/books/${context.bookId}/open_item_positions/`))) {
    const next = write.data, before = (await tx.get(db.doc(write.path))).data();
    accountingNeed(next.companyId === context.companyId && next.bookId === context.bookId && ["charge", "return_credit"].includes(next.kind), "Open-item position scope/kind is invalid.");
    accountingNeed(write.method === "create" ? !before : !!before, "Open-item create/update state is inconsistent.");
    const delta = accountingUnits(next.remainingUnits) - (before ? accountingUnits(before.remainingUnits) : 0n);
    add(itemTotals, `${next.customerId}:${next.kind}`, delta);
  }
  const partyTotals = new Map<string, bigint>();
  for (const e of controls.filter(e => e.kind !== "cash")) add(partyTotals, `${e.dimensions.customerId}:${e.kind === "receivable" ? "charge" : "return_credit"}`, BigInt(e.afterUnits) - BigInt(e.beforeUnits));
  equalTotals(itemTotals, partyTotals, "Open-item/party control delta");
  for (const write of writes.filter(w => w.path.includes("/cash_balances/"))) accountingNeed(controls.some(c => c.kind === "cash" && c.positionPath === write.path), "Cash position lacks a journal control effect.");
  const stockPaths = new Set<string>(), transferLines = new Map<string, {delta: bigint; count: number; holders: Set<string>; types: Set<string>}>();
  for (const stock of stocks) {
    accountingNeed(!stockPaths.has(stock.positionPath), "Stock positions must be grouped before posting.");stockPaths.add(stock.positionPath);
    configurationId(stock.itemId, "stock item");configurationId(stock.holderId, "stock holder");
    accountingNeed(Number.isSafeInteger(stock.quantityScale) && stock.quantityScale >= 0 && stock.quantityScale <= 6 && typeof stock.unit === "string" && stock.unit.length > 0 && stock.movementPaths.length > 0, "Stock unit contract is invalid.");
    const write = byPath.get(stock.positionPath), snapshot = await tx.get(db.doc(stock.positionPath));
    accountingNeed(write && write.method !== "create", "Stock requires an evidenced existing position.");
    const before = accountingUnits(stock.beforeUnits), after = accountingUnits(stock.afterUnits);
    accountingSame(snapshot.data()?.[stock.field], before.toString(), "Stock position before");accountingSame(write.data[stock.field], after.toString(), "Stock position after");
    let change = 0n;
    for (const path of stock.movementPaths) {
      const movement = byPath.get(path);accountingNeed(movement?.method === "create", "Stock effect requires immutable movement legs.");
      const m = movement.data, amount = accountingUnits(m.quantityUnits);
      accountingNeed(m.companyId === context.companyId && m.itemId === stock.itemId && m.unit === stock.unit && m.quantityScale === stock.quantityScale && m.holderType === stock.holderType && m.holderId === stock.holderId && amount > 0n && ["in", "out"].includes(m.direction), "Stock movement dimensions differ from the position.");
      const delta = m.direction === "in" ? amount : -amount;change += delta;
      if (stock.purpose === "transfer") {
        const key = accountingCanonical([m.sourceId, m.lineId, m.itemId, m.unit, m.quantityScale]);const group = transferLines.get(key) ?? {delta: 0n, count: 0, holders: new Set<string>(), types: new Set<string>()};
        group.delta += delta;group.count++;group.holders.add(`${stock.holderType}:${stock.holderId}`);group.types.add(stock.holderType);transferLines.set(key, group);
      }
    }
    accountingSame((after - before).toString(), change.toString(), "Stock movement/position delta");
  }
  for (const group of transferLines.values()) accountingNeed(group.delta === 0n && group.count === 2 && group.holders.size === 2 && group.types.has("warehouse") && group.types.has("representative"), "A warehouse/custody transfer must conserve each original line across two authorized holders.");
  for (const write of writes) if (write.path.startsWith("items/") || write.path.includes("/rep_inventory_balances/")) accountingNeed(stockPaths.has(write.path), "Quantity position lacks a stock effect.");
  if (!journal) accountingNeed(stocks.length > 0 && controls.length === 0, "A journal-free event must have only physical stock effects.");
}
