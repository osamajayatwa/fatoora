const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  calculateInvoiceTotals,
  persistedInvoiceLine,
} = require("../lib/trusted/totals");

test("trusted custom line preserves metadata and participates in totals", () => {
  const totals = calculateInvoiceTotals([
    {
      lineId: "catalog-1",
      lineType: "catalog",
      itemId: "item-1",
      itemName: "DSS pump",
      description: "Invoice-local description",
      quantity: 1,
      unitPrice: 250,
      discount: 0,
      taxPercent: 0,
    },
    {
      lineId: "custom-1",
      lineType: "custom",
      itemId: null,
      itemName: "Installation",
      description: "Installation and commissioning",
      quantity: 1,
      unitPrice: 50,
      discount: 0,
      taxPercent: 0,
    },
  ]);
  assert.equal(totals.grandTotal, 300);
  assert.deepEqual(persistedInvoiceLine(totals.items[1]), {
    lineId: "custom-1",
    lineType: "custom",
    itemId: null,
    itemName: "Installation",
    description: "Installation and commissioning",
    itemCode: "",
    unit: "",
    quantity: 1,
    unitPrice: 50,
    discount: 0,
    taxPercent: 0,
    subtotal: 50,
    taxAmount: 0,
    total: 50,
  });
});

test("trusted totals preserve legacy classification and reject unsupported types", () => {
  const legacyCatalog = calculateInvoiceTotals([{
    itemId: "item-1",
    itemName: "Pump",
    quantity: 1,
    unitPrice: 1,
    taxPercent: 0,
  }]).items[0];
  assert.equal(legacyCatalog.lineType, "catalog");
  assert.equal(legacyCatalog.lineTypeExplicit, false);

  const legacyManual = calculateInvoiceTotals([{
    itemId: "manual-1",
    itemName: "Legacy service",
    quantity: 1,
    unitPrice: 1,
    taxPercent: 0,
  }]).items[0];
  assert.equal(legacyManual.lineType, "custom");
  assert.equal(legacyManual.lineTypeExplicit, false);

  assert.throws(() => calculateInvoiceTotals([{
    lineType: "informational",
    quantity: 1,
    unitPrice: 1,
    taxPercent: 0,
  }]));
  assert.throws(() => calculateInvoiceTotals([{
    lineType: "custom",
    quantity: 1,
    unitPrice: 0,
    taxPercent: 0,
  }]));
});
