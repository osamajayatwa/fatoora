const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  CASH_RECONCILIATION_SCHEMA_VERSION,
  analyzeCashRecords,
  balanceMatches,
  cashBalanceDocumentId,
  parseOptions,
} = require("../scripts/cash_reconciliation_common");

const companyId = "company-a";

test("empty movement history produces an explicit zero company balance", () => {
  const plan = analyzeCashRecords({companyId});
  assert.equal(plan.issueCount, 0);
  assert.equal(plan.scannedMovementCount, 0);
  assert.deepEqual(accountValues(plan), {
    company_cash: {count: 0, in: 0, out: 0, balance: 0, stored: null},
  });
});

test("company cash totals mixed IN and OUT movements", () => {
  const plan = analyzeCashRecords({
    companyId,
    movements: [
      movement("company-in", {amount: 100, direction: "in"}),
      movement("company-out", {
        amount: 35.125,
        direction: "out",
        movementType: "expense",
        sourceCollection: "expenses",
      }),
    ],
  });
  assert.equal(plan.issueCount, 0);
  assert.deepEqual(accountValues(plan).company_cash, {
    count: 2,
    in: 100,
    out: 35.125,
    balance: 64.875,
    stored: null,
  });
});

test("company cash opening balance is accepted as full-history cash in", () => {
  const plan = analyzeCashRecords({
    companyId,
    movements: [movement("company_cash_opening_balance", {
      amount: 77.375,
      movementType: "opening_balance",
      sourceCollection: "cash_movements",
      sourceId: "company_cash_opening_balance",
      date: new Date("2026-07-30T00:00:00.000Z"),
    })],
  });

  assert.equal(plan.issueCount, 0);
  assert.equal(plan.validMovementCount, 1);
  assert.equal(plan.accounts[0].calculatedBalance, 77.375);
});

test("multiple representative accounts remain isolated", () => {
  const plan = analyzeCashRecords({
    companyId,
    representativeIds: ["rep-a", "rep-b", "rep-empty"],
    movements: [
      movement("rep-a-in", {cashAccount: "rep_cash", salesRepId: "rep-a", amount: 40}),
      movement("rep-a-out", {
        cashAccount: "rep_cash",
        salesRepId: "rep-a",
        amount: 10,
        direction: "out",
        movementType: "expense",
        sourceCollection: "expenses",
      }),
      movement("rep-b-in", {cashAccount: "rep_cash", salesRepId: "rep-b", amount: 25}),
    ],
  });
  assert.equal(plan.issueCount, 0);
  const values = accountValues(plan);
  assert.equal(values["rep_rep-a"].balance, 30);
  assert.equal(values["rep_rep-b"].balance, 25);
  assert.equal(values["rep_rep-empty"].balance, 0);
  assert.equal(values.company_cash.balance, 0);
});

test("malformed, missing-rep, ambiguous, unsupported, and duplicate movements block apply", () => {
  const duplicateA = movement("duplicate-a", {sourceId: "same-source"});
  const duplicateB = movement("duplicate-b", {sourceId: "same-source"});
  const plan = analyzeCashRecords({
    companyId,
    movements: [
      movement("missing-rep", {cashAccount: "rep_cash", salesRepId: ""}),
      movement("bad-amount", {amount: Number.NaN}),
      movement("ambiguous", {cashAccount: ""}),
      movement("unsupported-account", {cashAccount: "bank"}),
      movement("unsupported-type", {movementType: "manual"}),
      duplicateA,
      duplicateB,
      movement("bad-date", {date: null}),
      {id: "bad-id", data: {...movement("other").data, id: "different-id"}},
    ],
  });
  assert.ok(plan.issueCount >= 7);
  assert.equal(plan.issueCounts.missing_sales_rep_id, 1);
  assert.equal(plan.issueCounts.malformed_amount, 1);
  assert.equal(plan.issueCounts.ambiguous_cash_account, 1);
  assert.equal(plan.issueCounts.unsupported_cash_account, 1);
  assert.equal(plan.issueCounts.unsupported_movement_type, 1);
  assert.equal(plan.issueCounts.duplicate_logical_movement, 1);
  assert.equal(plan.issueCounts.malformed_movement_date, 1);
  assert.equal(plan.issueCounts.malformed_movement_id, 1);
});

test("a negative full-history cash balance is unresolved", () => {
  const plan = analyzeCashRecords({
    companyId,
    movements: [movement("company-out", {
      amount: 1,
      direction: "out",
      movementType: "expense",
      sourceCollection: "expenses",
    })],
  });
  assert.equal(plan.accounts[0].calculatedBalance, -1);
  assert.equal(plan.issueCounts.negative_calculated_balance, 1);
});

test("a reconciled balance is idempotently recognized on a second run", () => {
  const movements = [
    movement("company-in", {amount: 20}),
    movement("company-out", {
      amount: 5,
      direction: "out",
      movementType: "expense",
      sourceCollection: "expenses",
    }),
  ];
  const initial = analyzeCashRecords({companyId, movements});
  const account = initial.accounts[0];
  const stored = reconciledStoredBalance(account);
  const repeated = analyzeCashRecords({
    companyId,
    movements,
    storedBalances: [{id: "company_cash", data: stored}],
  });
  assert.equal(repeated.issueCount, 0);
  assert.equal(repeated.accounts[0].difference, 0);
  assert.equal(balanceMatches(repeated.accounts[0], companyId), true);
});

test("maintenance CLI is dry-run by default and apply requires exact confirmation", () => {
  const dryRun = parseOptions([
    "--project=fatoora-test",
    "--company=company-a",
    "--page-size=25",
  ]);
  assert.equal(dryRun.apply, false);
  assert.equal(dryRun.pageSize, 25);
  assert.throws(
    () => parseOptions([
      "--project=fatoora-test",
      "--company=company-a",
      "--apply",
    ]),
    /confirm-project/,
  );
  const apply = parseOptions([
    "--project=fatoora-test",
    "--company=company-a",
    "--apply",
    "--confirm-project=fatoora-test",
    "--confirm-company=company-a",
  ]);
  assert.equal(apply.apply, true);
});

test("cash balance document IDs match the trusted ledger contract", () => {
  assert.equal(cashBalanceDocumentId("company_cash"), "company_cash");
  assert.equal(cashBalanceDocumentId("rep_cash", "rep-a"), "rep_rep-a");
  assert.throws(() => cashBalanceDocumentId("rep_cash", ""), /salesRepId/);
});

function movement(id, overrides = {}) {
  return {
    id,
    data: {
      id,
      companyId,
      amount: 10,
      direction: "in",
      cashAccount: "company_cash",
      salesRepId: "",
      movementType: "receipt",
      sourceCollection: "receipts",
      sourceId: id,
      referenceId: id,
      date: new Date("2026-08-05T12:00:00.000Z"),
      ...overrides,
    },
  };
}

function accountValues(plan) {
  return Object.fromEntries(plan.accounts.map((account) => [
    account.documentId,
    {
      count: account.movementCount,
      in: account.totalIn,
      out: account.totalOut,
      balance: account.calculatedBalance,
      stored: account.storedBalance,
    },
  ]));
}

function reconciledStoredBalance(account) {
  return {
    id: account.documentId,
    companyId,
    cashAccount: account.cashAccount,
    salesRepId: account.salesRepId,
    amount: account.calculatedBalance,
    lastMovementId: account.lastMovementId,
    schemaVersion: CASH_RECONCILIATION_SCHEMA_VERSION,
    reconciliation: {
      schemaVersion: CASH_RECONCILIATION_SCHEMA_VERSION,
      mode: "full_history",
      sourceCollection: "cash_movements",
      movementCount: account.movementCount,
      totalIn: account.totalIn,
      totalOut: account.totalOut,
      calculatedBalance: account.calculatedBalance,
      sourceLastMovementId: account.lastMovementId,
    },
  };
}
