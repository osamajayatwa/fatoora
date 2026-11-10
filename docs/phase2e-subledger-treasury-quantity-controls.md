# Phase 2E — Customer, treasury and quantity controls

2026-11-11, Asia/Amman. Local accounting-foundation implementation, following
[Phase 2D](phase2d-atomic-posting-engine.md). Posting remains default-off and
restricted to the dedicated synthetic loopback Firestore emulator. No deployment,
active-book switch, real opening import or production policy approval occurred.

## Delivered scope

The existing trusted invoice, receipt, sales-return, cash-ledger, inventory and
custody modules expose shared internal preparers. They compose domain effects
with the canonical event, balanced journal where applicable, source/request keys,
audit, outbox and posting lane in one SDK transaction. The existing settlement
adapter now uses the exact treasury preparer through its original transaction
seam. There are no new business callables or duplicate customer/stock workflows.

The broad migration of existing business callables, repositories, reports and UI
is Phase 3. These preparers do not by themselves enable double-entry posting for
every invoice, receipt or return. Current source eligibility, permissions, tax
calculation, return quantities and cumulative refund limits remain responsibilities
of the registered business workflow when it adopts the preparers.

## Customer controls

Each book has immutable `open_items` principals, mutable `open_item_positions`,
immutable `allocations`, and an exact per-customer `party_positions` control.
Receivables and return credits remain distinct, with
`signedDebtUnits = receivableUnits - returnCreditUnits`.

- Invoice charges preserve the gross original principal. Initial payments create
  an allocation and reduce remaining AR in the same event as cash and the journal.
  Fully paid invoices retain a closed principal rather than losing their history.
- Ordinary receipts cannot exceed positive signed debt. They allocate oldest due
  date, then original date, then stable item ID. Selection reads at most 101 rows
  and consumes at most 100. Insufficient bounded coverage rejects the whole
  transaction; there is no partially posted cash or inferred unapplied receipt.
- Unpaid returns reduce the specific original charge. Paid portions can create
  a separate return-credit liability. A combined partial return updates both
  controls through one party write. Credit application consumes evidenced credit
  and AR without a cash movement.

Every principal and current position must have immutable atomic event evidence
or an explicit synthetic opening. Missing history never becomes zero. Original
principals remain unchanged after allocations. Concurrent receipts serialize on
the same party/item positions and cannot consume the same debt twice.

Before writing, the engine independently compares journal control-account and
dimension deltas with exact cash/customer position changes. Open-item remaining
deltas must also equal the party controls. A balanced journal alone cannot change
cash or AR without the corresponding subledger effects. Advances, general
unapplied receipts, supplier/AP controls and new refund workflows are not enabled.

## Exact treasury

The settlement adapter accepts either the original checked three-decimal numeric
amount or explicit `amountUnits` with an independent declared `moneyScale`.
Native amounts support the existing 30-digit unit range and scales zero through
six. Calculations, sufficiency checks, sequence updates and journal lines use
integer units. Current cash positions require the actual holder, currency, scale,
immutable movement head and matching atomic canonical event/opening.

Compatibility numbers are supplied only when they round-trip exactly. Otherwise
they are explicitly null with unavailable coverage; unknown or unrepresentable
values never become zero. The legacy financial-ledger projection uses a schema-4
`exact_reader_required` sentinel when the v3 numeric contract cannot represent
the posting. The v3 row projector rejects that sentinel. This is a migration
boundary, not proof that legacy cached summaries or UI support native amounts;
canonical readers/reconciliation in 2G and workflow/report integration in Phase 3
must complete before activation.

Original Phase 2D three-decimal request/economic identities are preserved. An
upgrade check generated evidence using actual commit `cf03c1c`, recovered it with
the new engine and successfully posted the next settlement against the same cash
positions.

## Quantity-only inventory

Exact warehouse quantities extend existing root `items`; representative custody
extends existing `rep_inventory_balances`. Immutable legs use the existing
`stock_movements` and `rep_inventory_movements` collections. Each position carries
its unit, independent quantity scale, sequence, last movement and event marker.
Every original transfer line must conserve quantity across exactly one warehouse
and one approved representative. Repeated product lines keep separate movement
identities while their final position write is grouped. Shortages reject exactly,
without epsilon tolerances.

There is no purchase-cost requirement, inventory valuation or COGS calculation.
Reference selling-price/name edits do not invalidate quantity evidence or reprice
history. Rules allow an absent/null purchase cost on an otherwise valid catalog
edit and prevent unit changes once an exact stock book is attached. Exact
quantity/head fields remain server-owned.

A physical-only transfer has a canonical quantity event and a null journal ID;
it does not create a fabricated zero-money journal. Invoice/return adapters can
combine physical changes with money/customer effects in the same event.

## Atomic evidence and capacity

Large effect manifests use immutable chunks created with the source/event,
validated by digest, scope, count and SDK commit time. Small events retain inline
evidence. Recovery checks immutable sources, principals, allocations and chunks
while allowing mutable positions to advance after the original posting.

The application write budget increases from 400 to **480**: a 100-line transfer
with distinct products needs 200 movement legs plus 200 position updates before
authority/evidence writes. Its measured synthetic first commit used **438 reads,
423 writes, 1,142,017 serialized write bytes and 13 evidence chunks**. Budgets
remain 600 document reads, 512 KiB per serialized document and 4 MiB serialized
write data. This is emulator acceptance of the bounded operation, not cloud
throughput, indexing-cost or network-size certification. Required open-item FIFO
index and evidence index exemptions are included in the local index manifest.

## Verification and next phase

The independently exported staged backend builds with only committed sources and
installed dependencies. **188 foundation tests pass**, covering configuration,
journals, transaction guards, exact treasury, customer allocations, combined
sale/return controls, stock conservation, 100-line capacity, concurrency,
interruption/rollback, retry and missing/corrupt evidence. **128 existing
backend/Rules regression tests pass** in the working tree. Rules deny client
access to all new book control/evidence collections and protect native quantity
fields. Phase 2E changes no Flutter screens; broader UI integration stays in
Phase 3. Local logs and capacity evidence are under `output/phase2e/`.

Run the focused suite only with the dedicated loopback emulator selected:

```text
npm --prefix functions run test:accounting-controls
npm --prefix functions run test:accounting-posting
npm --prefix functions run test:accounting-configuration
```

Phase 2F is next: linked domain-aware corrections/reversals and period
close/reopen. Phase 2G follows with minimal GL/trial-balance readers,
reconciliations and integrated foundation acceptance. Real financial acceptance,
historical import and production activation remain separate gates.
