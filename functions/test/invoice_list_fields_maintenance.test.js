const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  buildInvoiceListFieldUpdates,
  buildSearchKeywords,
  parseOptions,
} = require("../scripts/invoice_list_fields_common");

test("backfill adds safe query fields without overwriting stored values", () => {
  const createdAt = new Date("2026-08-01T12:00:00.000Z");
  const result = buildInvoiceListFieldUpdates({
    invoiceNumber: "INV-42",
    invoiceDate: createdAt,
    invoiceType: "regular",
    invoiceStatus: "confirmed",
    grandTotal: 100,
    paidAmount: 25,
    remainingAmount: 75,
    customerId: "customer-1",
    salesRepId: "rep-1",
    salesRepName: "Stored Rep",
    createdByName: "Different Creator",
    customerSnapshot: {
      id: "customer-1",
      name: "Acme Trading",
      phone: "+962790000000",
    },
    returnedTotal: 0,
    returnInvoiceIds: [],
    searchKeywords: ["legacy-keyword"],
  }, {createTime: createdAt});

  assert.equal(result.updates.invoiceNumberLower, "inv-42");
  assert.equal(result.updates.customerNameLower, "acme trading");
  assert.equal(result.updates.paymentStatus, "partiallyPaid");
  assert.equal(result.updates.returnStatus, "none");
  assert.equal(result.updates.createdAt, createdAt);
  assert.equal(result.updates.salesRepName, undefined);
  assert.ok(result.updates.searchKeywords.includes("legacy-keyword"));
  assert.ok(result.updates.searchKeywords.includes("+962790000000"));
  assert.deepEqual(result.unresolved, []);
});

test("backfill flags ambiguous returned legacy invoices for review", () => {
  const date = new Date("2026-08-01T00:00:00.000Z");
  const result = buildInvoiceListFieldUpdates({
    invoiceNumber: "INV-43",
    invoiceDate: date,
    createdAt: date,
    invoiceType: "regular",
    invoiceStatus: "confirmed",
    grandTotal: 100,
    paidAmount: 100,
    remainingAmount: 0,
    customerId: "customer-1",
    salesRepId: "rep-1",
    salesRepName: "Rep One",
    customerSnapshot: {name: "Customer"},
    returnedTotal: 20,
    returnInvoiceIds: ["return-1"],
  });

  assert.equal(result.updates.returnStatus, undefined);
  assert.ok(result.unresolved.includes("returnStatus"));
});

test("search keywords include prefixes for all required search fields", () => {
  const keywords = buildSearchKeywords([
    "INV-2026-001",
    "Customer Name",
    "+96279",
    "Sales Representative",
  ]);
  assert.ok(keywords.includes("inv"));
  assert.ok(keywords.includes("cust"));
  assert.ok(keywords.includes("+962"));
  assert.ok(keywords.includes("sales"));
  assert.ok(keywords.includes("rep"));
});

test("apply mode requires exact project and company confirmation", () => {
  assert.throws(() => parseOptions([]), /--project/);
  assert.throws(
    () => parseOptions([
      "--project=fatoora-test",
      "--company=company-a",
      "--apply",
    ]),
    /--confirm-project/,
  );
  const options = parseOptions([
    "--project=fatoora-test",
    "--company=company-a",
    "--apply",
    "--confirm-project=fatoora-test",
    "--confirm-company=company-a",
  ]);
  assert.equal(options.apply, true);
});
