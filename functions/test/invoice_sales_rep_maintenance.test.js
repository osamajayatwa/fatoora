const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  analyzeInvoiceOwnership,
  inferBackfillOwner,
  parseOptions,
} = require("../scripts/invoice_sales_rep_common");

test("audit distinguishes missing, empty, and conflicting ownership", () => {
  const context = ownershipContext({
    "invoice-from-quote": ["rep-a"],
  });

  const missing = analyzeInvoiceOwnership(
    "invoice-missing",
    { createdByUid: "rep-a", invoiceType: "regular", invoiceStatus: "draft" },
    context,
  );
  assert.equal(missing.hasSalesRepId, false);
  assert.equal(missing.salesRepId, "");

  const empty = analyzeInvoiceOwnership(
    "invoice-empty",
    { salesRepId: null, createdByUid: "rep-a" },
    context,
  );
  assert.equal(empty.hasSalesRepId, true);
  assert.equal(empty.salesRepId, "");

  const conflict = analyzeInvoiceOwnership(
    "invoice-from-quote",
    { salesRepId: "rep-b", createdByUid: "admin" },
    context,
  );
  assert.deepEqual(conflict.mismatchReasons, [
    "differs_from_converted_quotation",
  ]);
});

test("backfill prefers converted quotation ownership over admin creator", () => {
  const decision = inferBackfillOwner(
    "invoice-from-quote",
    { createdByUid: "admin", createdByRole: "admin" },
    ownershipContext({ "invoice-from-quote": ["rep-a"] }),
  );

  assert.deepEqual(decision, {
    action: "update",
    salesRepId: "rep-a",
    source: "converted_quotation",
  });
});

test("backfill uses a valid creator when no quotation evidence exists", () => {
  const decision = inferBackfillOwner(
    "legacy-invoice",
    { createdByUid: "rep-b", createdByRole: "sales_rep" },
    ownershipContext(),
  );

  assert.deepEqual(decision, {
    action: "update",
    salesRepId: "rep-b",
    source: "created_by_uid",
  });
});

test("backfill skips ambiguous, unknown, and name-only ownership", () => {
  const ambiguous = inferBackfillOwner(
    "ambiguous",
    { createdByUid: "admin" },
    ownershipContext({ ambiguous: ["rep-a", "rep-b"] }),
  );
  assert.deepEqual(ambiguous, {
    action: "skip",
    reason: "ambiguous_quotation_owners",
  });

  const unknown = inferBackfillOwner(
    "unknown",
    { createdByUid: "deleted-user" },
    ownershipContext(),
  );
  assert.deepEqual(unknown, {
    action: "skip",
    reason: "owner_user_missing",
  });

  const nameOnly = inferBackfillOwner(
    "name-only",
    { salesRepName: "Unresolved Rep" },
    ownershipContext(),
  );
  assert.deepEqual(nameOnly, {
    action: "skip",
    reason: "sales_rep_name_without_uid",
  });
});

test("maintenance commands require an explicit project", () => {
  assert.throws(() => parseOptions([]), /--project/);
  const options = parseOptions([
    "--project=fatoora-test",
    "--company=company-a",
    "--max-writes=25",
  ]);
  assert.equal(options.projectId, "fatoora-test");
  assert.equal(options.companyId, "company-a");
  assert.equal(options.maxWrites, 25);
  assert.equal(options.apply, false);
});

function ownershipContext(quotationAssignments = {}) {
  const quotationOwners = new Map();
  for (const [invoiceId, ownerIds] of Object.entries(quotationAssignments)) {
    quotationOwners.set(
      invoiceId,
      new Map(ownerIds.map((ownerId) => [ownerId, { quotationIds: [] }])),
    );
  }
  return {
    quotationOwners,
    users: new Map([
      ["admin", { role: "admin" }],
      ["rep-a", { role: "sales_rep" }],
      ["rep-b", { role: "sales_rep" }],
    ]),
  };
}
