import {DocumentData, Timestamp} from "firebase-admin/firestore";
import {
  buildFinancialLedgerEntry,
  cashAccount,
  collectionAccount,
  companyCashAccount,
  customerAccount,
  expensesAccount,
  openingBalanceEquityAccount,
  repCashAccount,
  repPayableAccount,
  salesAccount,
} from "./financial_ledger";

export interface InvoiceLedgerMappingInput {
  companyId: string;
  invoiceId: string;
  invoiceNumber: string;
  invoiceDate: Timestamp;
  grandTotal: number;
  initialCashAmount: number;
  initialCashAccount: string;
  customerId: string;
  customerName: string;
  salesRepId: string;
  salesRepName: string;
  notes: string;
}

export function buildInvoiceFinancialLedgerEntries(
  input: InvoiceLedgerMappingInput,
): DocumentData[] {
  const entries: DocumentData[] = [];
  if (input.initialCashAmount > 0) {
    entries.push(buildFinancialLedgerEntry({
      id: `invoice_${input.invoiceId}_sales_cash`,
      companyId: input.companyId,
      occurredAt: input.invoiceDate,
      type: "invoice_sale",
      component: "cash_sale",
      description: `Invoice ${input.invoiceNumber}`,
      amount: input.initialCashAmount,
      debit: cashAccount(
        input.initialCashAccount,
        input.salesRepId,
        input.salesRepName,
      ),
      credit: salesAccount(),
      referenceType: "invoice",
      referenceId: input.invoiceId,
      referenceNumber: input.invoiceNumber,
      sourceCollection: "invoices",
      sourceId: input.invoiceId,
      customerId: input.customerId,
      customerName: input.customerName,
      salesRepId: input.salesRepId,
      salesRepName: input.salesRepName,
      ownershipSource: "invoice.salesRepId",
      paymentMethod: "cash",
      notes: input.notes,
      metrics: {
        sales: input.initialCashAmount,
        cashSales: input.initialCashAmount,
        companyCashNet: input.initialCashAccount === "company_cash"
          ? input.initialCashAmount
          : 0,
        repCashIn: input.initialCashAccount === "rep_cash"
          ? input.initialCashAmount
          : 0,
      },
    }));
  }
  const creditAmount = roundMoney(input.grandTotal - input.initialCashAmount);
  if (creditAmount > 0) {
    entries.push(buildFinancialLedgerEntry({
      id: `invoice_${input.invoiceId}_sales_receivable`,
      companyId: input.companyId,
      occurredAt: input.invoiceDate,
      type: "invoice_sale",
      component: "credit_sale",
      description: `Invoice ${input.invoiceNumber}`,
      amount: creditAmount,
      debit: customerAccount(input.customerId, input.customerName),
      credit: salesAccount(),
      referenceType: "invoice",
      referenceId: input.invoiceId,
      referenceNumber: input.invoiceNumber,
      sourceCollection: "invoices",
      sourceId: input.invoiceId,
      customerId: input.customerId,
      customerName: input.customerName,
      salesRepId: input.salesRepId,
      salesRepName: input.salesRepName,
      ownershipSource: "invoice.salesRepId",
      paymentMethod: "credit",
      notes: input.notes,
      metrics: {
        sales: creditAmount,
        creditSales: creditAmount,
        receivables: creditAmount,
      },
    }));
  }
  return entries;
}

export interface ReceiptLedgerOwnerGroup {
  salesRepId: string;
  salesRepName: string;
  amount: number;
  ownershipSource: string;
}

export function receiptAllocationGroups(
  entries: Array<{id: string; amount: number; data: Record<string, unknown>}>,
  unallocated: number,
  collectorSalesRepId: string,
  collectorSalesRepName: string,
): ReceiptLedgerOwnerGroup[] {
  const groups = new Map<string, ReceiptLedgerOwnerGroup>();
  for (const entry of entries) {
    const salesRepId = scalarString(entry.data.salesRepId);
    const key = salesRepId || "unassigned";
    const existing = groups.get(key) ?? {
      salesRepId,
      salesRepName: scalarString(entry.data.salesRepName),
      amount: 0,
      ownershipSource: salesRepId
        ? "receipt.invoiceAllocations.salesRepId"
        : "unresolved",
    };
    existing.amount = roundMoney(existing.amount + entry.amount);
    groups.set(key, existing);
  }
  if (unallocated > 0) {
    const key = collectorSalesRepId || "unassigned";
    const existing = groups.get(key) ?? {
      salesRepId: collectorSalesRepId,
      salesRepName: collectorSalesRepName,
      amount: 0,
      ownershipSource: collectorSalesRepId
        ? "receipt.collector.salesRepId"
        : "unresolved",
    };
    existing.amount = roundMoney(existing.amount + unallocated);
    groups.set(key, existing);
  }
  return [...groups.values()].filter((entry) => entry.amount > 0);
}

export interface ReceiptLedgerMappingInput {
  companyId: string;
  receiptId: string;
  receiptNumber: string;
  receiptDate: Timestamp;
  paymentMethod: string;
  cashAccount: string;
  cashAccountSalesRepId: string;
  cashAccountSalesRepName: string;
  customerId: string;
  customerName: string;
  notes: string;
  groups: ReceiptLedgerOwnerGroup[];
}

export function buildReceiptFinancialLedgerEntries(
  input: ReceiptLedgerMappingInput,
): DocumentData[] {
  const debit = input.paymentMethod === "cash"
    ? cashAccount(
      input.cashAccount,
      input.cashAccountSalesRepId,
      input.cashAccountSalesRepName,
    )
    : collectionAccount(input.paymentMethod);
  return input.groups.map((group) => buildFinancialLedgerEntry({
    id: `receipt_${input.receiptId}_collection_${encodeURIComponent(group.salesRepId || "unassigned")}`,
    companyId: input.companyId,
    occurredAt: input.receiptDate,
    type: "receipt",
    component: "customer_collection",
    description: `Receipt ${input.receiptNumber}`,
    amount: group.amount,
    debit,
    credit: customerAccount(input.customerId, input.customerName),
    referenceType: "receipt",
    referenceId: input.receiptId,
    referenceNumber: input.receiptNumber,
    sourceCollection: "receipts",
    sourceId: input.receiptId,
    customerId: input.customerId,
    customerName: input.customerName,
    salesRepId: group.salesRepId,
    salesRepName: group.salesRepName,
    ownershipSource: group.ownershipSource,
    paymentMethod: input.paymentMethod,
    notes: input.notes,
    metrics: {
      receipts: group.amount,
      receivables: -group.amount,
      companyCashNet: input.paymentMethod === "cash" &&
        input.cashAccount === "company_cash" ? group.amount : 0,
      repCashIn: input.paymentMethod === "cash" &&
        input.cashAccount === "rep_cash" ? group.amount : 0,
    },
  }));
}

export type ExpenseFundingSource =
  "company_cash" | "personal_cash" | "rep_collected_cash";

export interface ExpenseLedgerMappingInput {
  companyId: string;
  expenseId: string;
  expenseDate: Timestamp;
  amount: number;
  fundingSource: ExpenseFundingSource;
  description: string;
  salesRepId: string;
  salesRepName: string;
  notes: string;
}

export function buildExpenseFinancialLedgerEntry(
  input: ExpenseLedgerMappingInput,
): DocumentData {
  const companyFunded = input.fundingSource === "company_cash";
  const personallyFunded = input.fundingSource === "personal_cash";
  return buildFinancialLedgerEntry({
    id: `expense_${input.expenseId}_posted`,
    companyId: input.companyId,
    occurredAt: input.expenseDate,
    type: "expense",
    component: companyFunded
      ? "company_cash_expense"
      : personallyFunded
        ? "representative_personal_expense"
        : "representative_cash_expense",
    description: input.description,
    amount: input.amount,
    debit: expensesAccount(),
    credit: companyFunded
      ? companyCashAccount()
      : personallyFunded
        ? repPayableAccount(input.salesRepId, input.salesRepName)
        : repCashAccount(input.salesRepId, input.salesRepName),
    referenceType: "expense",
    referenceId: input.expenseId,
    referenceNumber: input.expenseId,
    sourceCollection: "expenses",
    sourceId: input.expenseId,
    salesRepId: input.salesRepId,
    salesRepName: input.salesRepName,
    ownershipSource: "expense.salesRepId",
    paymentMethod: personallyFunded ? "personal_cash" : "cash",
    notes: input.notes,
    metrics: {
      expenses: input.amount,
      companyCashNet: companyFunded ? -input.amount : 0,
      repCashOut: input.fundingSource === "rep_collected_cash" ? input.amount : 0,
    },
  });
}

export interface SalesReturnLedgerMappingInput {
  companyId: string;
  returnId: string;
  returnNumber: string;
  returnDate: Timestamp;
  grandTotal: number;
  cashRefundAmount: number;
  refundType: string;
  refundCashAccount: string;
  refundCashSalesRepId: string;
  customerId: string;
  customerName: string;
  salesRepId: string;
  salesRepName: string;
  quantity: number;
  reason: string;
}

export function buildSalesReturnFinancialLedgerEntries(
  input: SalesReturnLedgerMappingInput,
): DocumentData[] {
  const entries = [buildFinancialLedgerEntry({
    id: `sales_return_${input.returnId}_reversal`,
    companyId: input.companyId,
    occurredAt: input.returnDate,
    type: "sales_return",
    component: "sale_reversal",
    description: `Sales return ${input.returnNumber}`,
    amount: input.grandTotal,
    debit: salesAccount(),
    credit: customerAccount(input.customerId, input.customerName),
    referenceType: "sales_return",
    referenceId: input.returnId,
    referenceNumber: input.returnNumber,
    sourceCollection: "sales_returns",
    sourceId: input.returnId,
    customerId: input.customerId,
    customerName: input.customerName,
    salesRepId: input.salesRepId,
    salesRepName: input.salesRepName,
    ownershipSource: "originalInvoice.salesRepId",
    paymentMethod: input.refundType,
    quantity: input.quantity,
    notes: input.reason,
    metrics: {
      sales: -input.grandTotal,
      returns: input.grandTotal,
      receivables: -input.grandTotal,
    },
  })];
  if (input.cashRefundAmount > 0) {
    entries.push(buildFinancialLedgerEntry({
      id: `sales_return_${input.returnId}_cash_refund`,
      companyId: input.companyId,
      occurredAt: input.returnDate,
      type: "refund",
      component: "cash_refund",
      description: `Refund ${input.returnNumber}`,
      amount: input.cashRefundAmount,
      debit: customerAccount(input.customerId, input.customerName),
      credit: cashAccount(
        input.refundCashAccount,
        input.refundCashSalesRepId,
        input.salesRepName,
      ),
      referenceType: "sales_return",
      referenceId: input.returnId,
      referenceNumber: input.returnNumber,
      sourceCollection: "sales_returns",
      sourceId: input.returnId,
      customerId: input.customerId,
      customerName: input.customerName,
      salesRepId: input.salesRepId,
      salesRepName: input.salesRepName,
      ownershipSource: "originalInvoice.salesRepId",
      paymentMethod: "cash",
      notes: input.reason,
      metrics: {
        receivables: input.cashRefundAmount,
        companyCashNet: input.refundCashAccount === "company_cash"
          ? -input.cashRefundAmount
          : 0,
        repCashOut: input.refundCashAccount === "rep_cash"
          ? input.cashRefundAmount
          : 0,
      },
    }));
  }
  return entries;
}

export interface SettlementLedgerMappingInput {
  companyId: string;
  settlementId: string;
  settlementNumber: string;
  settlementDate: Timestamp;
  amount: number;
  salesRepId: string;
  salesRepName: string;
  notes: string;
}

export function buildSettlementFinancialLedgerEntry(
  input: SettlementLedgerMappingInput,
): DocumentData {
  return buildFinancialLedgerEntry({
    id: `settlement_${input.settlementId}_transfer`,
    companyId: input.companyId,
    occurredAt: input.settlementDate,
    type: "settlement",
    component: "rep_to_company_cash",
    description: `Cash settlement ${input.settlementNumber}`,
    amount: input.amount,
    debit: companyCashAccount(),
    credit: repCashAccount(input.salesRepId, input.salesRepName),
    referenceType: "settlement",
    referenceId: input.settlementId,
    referenceNumber: input.settlementNumber,
    sourceCollection: "settlements",
    sourceId: input.settlementId,
    salesRepId: input.salesRepId,
    salesRepName: input.salesRepName,
    ownershipSource: "settlement.salesRepId",
    paymentMethod: "cash",
    notes: input.notes,
    metrics: {
      settlements: input.amount,
      companyCashNet: input.amount,
      repCashOut: input.amount,
    },
  });
}

export interface CustomerOpeningLedgerMappingInput {
  companyId: string;
  transactionId: string;
  transactionDate: Timestamp;
  transactionType: "opening_balance" | "opening_balance_adjustment";
  openingBalanceType: string;
  signedAmount: number;
  customerId: string;
  customerName: string;
  salesRepId: string;
  salesRepName: string;
  notes: string;
}

export function buildCustomerOpeningFinancialLedgerEntry(
  input: CustomerOpeningLedgerMappingInput,
): DocumentData {
  const adjustment = input.transactionType === "opening_balance_adjustment";
  const signed = input.signedAmount;
  return buildFinancialLedgerEntry({
    id: adjustment
      ? `opening_balance_adjustment_${input.transactionId}_posted`
      : `opening_balance_${input.transactionId}_posted`,
    companyId: input.companyId,
    occurredAt: input.transactionDate,
    type: input.transactionType,
    component: adjustment
      ? signed > 0 ? "increase_receivable" : "decrease_receivable"
      : input.openingBalanceType,
    description: `${adjustment ? "Opening balance adjustment" : "Opening balance"} ${input.customerName}`,
    amount: Math.abs(signed),
    debit: signed > 0
      ? customerAccount(input.customerId, input.customerName)
      : openingBalanceEquityAccount(),
    credit: signed < 0
      ? customerAccount(input.customerId, input.customerName)
      : openingBalanceEquityAccount(),
    referenceType: "customer",
    referenceId: input.customerId,
    referenceNumber: adjustment ? "OPENING-ADJ" : "OPENING",
    sourceCollection: "customer_transactions",
    sourceId: input.transactionId,
    customerId: input.customerId,
    customerName: input.customerName,
    salesRepId: input.salesRepId,
    salesRepName: input.salesRepName,
    ownershipSource: input.salesRepId ? "postingSalesRep.uid" : "unassigned",
    notes: input.notes,
    metrics: {receivables: signed},
  });
}

export interface CompanyCashOpeningLedgerMappingInput {
  companyId: string;
  movementId: string;
  effectiveDate: Timestamp;
  amount: number;
  referenceNumber: string;
  notes: string;
}

export function buildCompanyCashOpeningFinancialLedgerEntry(
  input: CompanyCashOpeningLedgerMappingInput,
): DocumentData {
  return buildFinancialLedgerEntry({
    id: input.movementId === "company_cash_opening_balance"
      ? "opening_balance_company_cash_posted"
      : `opening_balance_company_cash_${input.movementId}`,
    companyId: input.companyId,
    occurredAt: input.effectiveDate,
    type: "opening_balance",
    component: "company_cash",
    description: "Company cash opening balance",
    amount: input.amount,
    debit: companyCashAccount(),
    credit: openingBalanceEquityAccount(),
    referenceType: "cash_movement",
    referenceId: input.movementId,
    referenceNumber: input.referenceNumber,
    sourceCollection: "cash_movements",
    sourceId: input.movementId,
    ownershipSource: "company",
    paymentMethod: "cash",
    notes: input.notes,
    metrics: {companyCashNet: input.amount},
  });
}

function roundMoney(value: number): number {
  return Math.round(value * 1000) / 1000;
}

function scalarString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}
