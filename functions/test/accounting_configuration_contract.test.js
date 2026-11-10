const {test} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
const {validateAccountingConfiguration: validate, accountingConfigurationReadiness: readiness, configurationDigest} = require("../lib/trusted/accounting_configuration_contract");
const fixture = () => JSON.parse(readFileSync(join(__dirname, "../../test/fixtures/accounting_configuration.json"), "utf8"));
test("complete synthetic draft has no activation or accounting approval", () => {
  const c = validate(fixture()), r = readiness(c);
  assert.equal(r.configurationComplete, true);assert.equal(r.postingEnabled, false);assert.equal(r.approvalStatus, "unreviewed");
  assert.deepEqual(r.activationBlockers, ["accountant_owner_confirmation", "opening_reconciliation", "posting_engine_acceptance"]);
  assert.equal(c.taxCodes[0].ratePercent, "16.000000");assert.equal(c.costCoverage, "not_recorded");
});
test("unknown opening stays unknown and incomplete, without manufactured balances", () => {
  const c = fixture();c.openingBoundary = {cutoverDate:null, financialCoverage:"unknown",quantityCoverage:"unknown",evidenceRefs:[],retainedEarningsTreatment:null};
  const r = readiness(validate(c));assert(r.missing.includes("financial_opening_evidence"));assert(r.missing.includes("opening_cutover_date"));assert.equal(r.configurationComplete, false);
});
const invalidCases = [
  ["injected posting gate", c => c.journalPostingEnabled = true],
  ["implicit currency", c => delete c.currency], ["lowercase currency", c => c.currency = "jod"],
  ["fractional scale", c => c.moneyScale = 2.5], ["excess quantity precision", c => c.quantityScale = 7],
  ["unsupported timezone", c => c.timezone = "UTC"], ["invalid fiscal day", c => {c.fiscalYearStartMonth = 2;c.fiscalYearStartDay = 30;}],
  ["cost inventory", c => c.inventoryMode = "costed"], ["zero cost coverage", c => c.costCoverage = "zero"],
  ["duplicate account ID", c => c.accounts[1].id = c.accounts[0].id],
  ["normalized code collision", c => {c.accounts[0].code = "abc";c.accounts[1].code = "ABC";}],
  ["cross-path account", c => c.accounts[0].id = "../other"],
  ["missing parent", c => c.accounts[1].parentId = "missing"],
  ["posting parent", c => c.accounts[0].postingAllowed = true],
  ["parent cycle", c => c.accounts[0].parentId = c.accounts[0].id],
  ["mixed hierarchy type", c => c.accounts[1].accountType = "liability"],
  ["group control account", c => c.accounts[0].control = "cash"],
  ["inactive mapped account", c => c.accounts[1].active = false],
  ["mapped group", c => c.mappings.companyCash = "assets"],
  ["wrong mapping control", c => c.mappings.receivables = "company-cash"],
  ["same cash control", c => c.mappings.representativeCash = "company-cash"],
  ["foreign mapping", c => c.mappings.sales = "foreign"],
  ["unknown mapping", c => c.mappings.ownerGuess = "equity"],
  ["invalid date", c => c.periods[0].startsOn = "2026-02-30"],
  ["empty period", c => c.periods[0].endsBefore = c.periods[0].startsOn],
  ["overlapping periods", c => c.periods.push({...c.periods[0],id:"overlap"})],
  ["period crosses fiscal year", c => c.periods[0].endsBefore = "2027-02-01"],
  ["client period close", c => c.periods[0].status = "closed"],
  ["numeric tax", c => c.taxCodes[0].ratePercent = 16],
  ["exponent tax", c => c.taxCodes[0].ratePercent = "1e1"],
  ["oversized tax", c => c.taxCodes[0].ratePercent = "100.000001"],
  ["overlapping tax revisions", c => c.taxCodes.push({...c.taxCodes[0]})],
  ["wrong tax account", c => c.taxCodes[0].outputAccountId = "sales"],
  ["tax without evidence", c => c.taxPolicy.evidenceRef = null],
  ["documented opening without evidence", c => c.openingBoundary.evidenceRefs = []],
  ["invented opening amount", c => c.openingBoundary.amount = "0"],
  ["account bound", c => {c.accounts = Array.from({length:81},(_,i)=>({...c.accounts[0],id:`a${i}`,code:`A${i}`}));}],
];
for (const [name, change] of invalidCases) test(`rejects ${name}`, () => {const c = fixture();change(c);assert.throws(() => validate(c), e => e.code === "invalid-argument");});
test("adjacent periods and dated tax revisions are accepted", () => {
  const c = fixture();c.periods.push({id:"dec",name:"December",startsOn:"2026-12-01",endsBefore:"2027-01-01"});
  c.taxCodes.push({...c.taxCodes[0],startsOn:"2027-01-01",endsBefore:"2028-01-01"});assert.equal(validate(c).periods.length, 2);
});
test("object key order and chart ordering do not change canonical config digest", () => {
  const a = fixture(), b = fixture();b.accounts.reverse();b.mappings = Object.fromEntries(Object.entries(b.mappings).reverse());
  assert.equal(configurationDigest(validate(a)), configurationDigest(validate(b)));
});
test("missing mappings and period coverage are explicit readiness gaps", () => {
  const c = fixture();c.mappings = {};c.openingBoundary.cutoverDate = "2026-12-01";
  const r = readiness(validate(c));assert(r.missing.includes("mapping_sales"));assert(r.missing.includes("opening_period_coverage"));
});
