const assert = require("node:assert/strict");
const {test} = require("node:test");
const {Timestamp} = require("firebase-admin/firestore");
const {
  buildAuditEvent,
  deterministicAuditId,
} = require("../lib/audit/audit_event_builder");
const {safeDiff} = require("../lib/audit/audit_diff");
const {
  isSensitiveField,
  safeValue,
  sanitizeString,
} = require("../lib/audit/audit_redaction");
const {ENTITY_CONFIGS} = require("../lib/audit/entity_audit_config");

const base = {
  sourceEventId: "evt-1",
  eventTime: "2026-07-29T10:00:00.000Z",
  authType: "unknown",
  authId: "admin",
  companyId: "default_company",
  entityId: "inv-1",
  entityPath: "companies/default_company/invoices/inv-1",
  config: ENTITY_CONFIGS.invoices,
  actor: {name: "Admin", role: "admin"},
};

test("deterministic IDs make duplicate deliveries idempotent", () => {
  assert.equal(
    deterministicAuditId("event", "companies/c/invoices/i"),
    deterministicAuditId("event", "companies/c/invoices/i"),
  );
  assert.notEqual(
    deterministicAuditId("event", "companies/c/invoices/i"),
    deterministicAuditId("event", "companies/c/invoices/j"),
  );
});

test("infers create and confirmation actions with shared operation ID", () => {
  const created = buildAuditEvent({
    ...base,
    after: {
      invoiceNumber: "INV-2026-000001", invoiceStatus: "draft",
      grandTotal: 100, operationId: "op-1", createdByUid: "admin",
    },
  });
  assert.equal(created.action, "invoice.created");
  assert.equal(created.operationId, "op-1");
  assert(created.occurredAt instanceof Timestamp);

  const confirmed = buildAuditEvent({
    ...base,
    before: {invoiceStatus: "draft"},
    after: {
      invoiceStatus: "confirmed", grandTotal: 100,
      remainingAmount: 60, paidAmount: 40, operationId: "op-1",
    },
  });
  assert.equal(confirmed.action, "invoice.confirmed");
  assert.equal(confirmed.financialImpact.documentTotal, 100);
  assert.equal(confirmed.financialImpact.receivableDelta, 60);
});

test("infers user role, approval, deactivation, expense, and transfer transitions", () => {
  const cases = [
    [ENTITY_CONFIGS.users, {role: "sales_rep"}, {role: "admin"},
      "user.role_changed"],
    [ENTITY_CONFIGS.users, {approvalStatus: "pending"},
      {approvalStatus: "approved"}, "user.approved"],
    [ENTITY_CONFIGS.users, {active: true}, {active: false},
      "user.deactivated"],
    [ENTITY_CONFIGS.expenses, {status: "pending"},
      {status: "approved"}, "expense.approved"],
    [ENTITY_CONFIGS.expenses, {status: "pending"},
      {status: "rejected"}, "expense.rejected"],
    [ENTITY_CONFIGS.inventory_transfers, {status: "draft"},
      {status: "confirmed"}, "inventory_transfer.confirmed"],
    [ENTITY_CONFIGS.sales_returns, {status: "draft"},
      {status: "confirmed"}, "sales_return.confirmed"],
  ];
  for (const [config, before, after, expected] of cases) {
    const event = buildAuditEvent({...base, config, before, after});
    assert.equal(event.action, expected);
  }
});

test("whitelists diffs and removes secrets and control characters", () => {
  const changes = safeDiff(
    {name: "Before", password: "old", ignored: "a"},
    {name: "After\nInjected", password: "new", ignored: "b"},
    ["name", "password"],
  );
  assert.deepEqual(changes.map((entry) => entry.field), ["name"]);
  assert.equal(changes[0].after, "After Injected");
  assert.equal(isSensitiveField("refreshToken"), true);
  assert.equal(sanitizeString("a\r\nb\u0000c"), "a b c");
  assert.deepEqual(safeValue({apiKey: "x", okay: "yes"}), {okay: "yes"});
});

test("derived events are hidden and capture inventory snapshots", () => {
  const event = buildAuditEvent({
    ...base,
    config: ENTITY_CONFIGS.stock_movements,
    entityId: "move-1",
    after: {
      itemId: "item-1", itemName: "Widget", movementType: "sale",
      beforeQuantity: 10, quantityDelta: -2, afterQuantity: 8,
      sourceId: "inv-1",
    },
  });
  assert.equal(event.displayInTimeline, false);
  assert.equal(event.operationId, "inv-1");
  assert.equal(event.inventoryImpact[0].afterQuantity, 8);
});

test("create-time confirmations and representative returns are semantic", () => {
  const confirmed = buildAuditEvent({
    ...base,
    after: {invoiceStatus: "confirmed", grandTotal: 40},
  });
  assert.equal(confirmed.action, "invoice.confirmed");
  const returned = buildAuditEvent({
    ...base,
    config: ENTITY_CONFIGS.rep_inventory_movements,
    after: {movementType: "transfer_return", quantity: 2},
  });
  assert.equal(returned.action, "rep_inventory.returned");
  assert.equal(returned.displayInTimeline, false);
});

test("opening balance and settings semantic actions are inferred", () => {
  const opening = buildAuditEvent({
    ...base,
    config: ENTITY_CONFIGS.customers,
    after: {name: "Customer", openingBalance: 25},
  });
  assert.equal(opening.action, "customer.opening_balance_created");
  const prefix = buildAuditEvent({
    ...base,
    config: ENTITY_CONFIGS.settings,
    before: {documentSettings: {invoicePrefix: "INV"}},
    after: {documentSettings: {invoicePrefix: "SI"}},
  });
  assert.equal(prefix.action, "document_prefix.changed");
});

test("company cash opening balance is a visible financial audit event", () => {
  const event = buildAuditEvent({
    ...base,
    config: ENTITY_CONFIGS.cash_movements,
    entityId: "company_cash_opening_balance",
    entityPath:
      "companies/default_company/cash_movements/company_cash_opening_balance",
    after: {
      id: "company_cash_opening_balance",
      movementType: "opening_balance",
      type: "opening_balance",
      direction: "in",
      cashAccount: "company_cash",
      amount: 250,
      balanceBefore: 0,
      balanceAfter: 250,
      effectiveDate: Timestamp.fromDate(new Date("2026-07-30T00:00:00.000Z")),
      operationId: "company_cash_opening_balance",
      createdByUid: "admin",
      createdByName: "Admin",
      createdByRole: "admin",
    },
  });

  assert.equal(event.action, "company_cash.opening_balance_created");
  assert.equal(event.displayInTimeline, true);
  assert.equal(event.financialImpact.companyCashDelta, 250);
  assert.equal(event.operationId, "company_cash_opening_balance");
});
