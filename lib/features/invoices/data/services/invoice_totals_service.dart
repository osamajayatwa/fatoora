import 'dart:math' as math;

import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';

class InvoiceTotals {
  const InvoiceTotals({
    required this.items,
    required this.subtotal,
    required this.totalDiscount,
    required this.totalTax,
    required this.grandTotal,
  });

  final List<InvoiceItemSnapshot> items;
  final double subtotal;
  final double totalDiscount;
  final double totalTax;
  final double grandTotal;
}

class InvoiceTotalsService {
  const InvoiceTotalsService();

  InvoiceItemSnapshot calculateLine(InvoiceItemSnapshot item) {
    final quantity = item.quantity.isFinite && item.quantity > 0
        ? item.quantity
        : 0.0;
    final unitPrice = item.unitPrice.isFinite && item.unitPrice > 0
        ? item.unitPrice
        : 0.0;
    final rawSubtotal = quantity * unitPrice;
    final discount = item.discount.isFinite
        ? item.discount.clamp(0, rawSubtotal).toDouble()
        : 0.0;
    final taxableAmount = math.max(rawSubtotal - discount, 0).toDouble();
    final taxPercent = item.taxPercent.isFinite
        ? item.taxPercent.clamp(0, 100).toDouble()
        : 0.0;
    final taxAmount = taxableAmount * (taxPercent / 100);
    final total = taxableAmount + taxAmount;

    return item.copyWith(
      quantity: round(quantity),
      unitPrice: round(unitPrice),
      discount: round(discount),
      taxPercent: round(taxPercent),
      subtotal: round(rawSubtotal),
      taxAmount: round(taxAmount),
      total: round(total),
    );
  }

  InvoiceTotals calculateInvoice(List<InvoiceItemSnapshot> rawItems) {
    final items = rawItems.map(calculateLine).toList(growable: false);
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.subtotal);
    final discount = items.fold<double>(0, (sum, item) => sum + item.discount);
    final tax = items.fold<double>(0, (sum, item) => sum + item.taxAmount);
    final total = items.fold<double>(0, (sum, item) => sum + item.total);
    return InvoiceTotals(
      items: items,
      subtotal: round(subtotal),
      totalDiscount: round(discount),
      totalTax: round(tax),
      grandTotal: round(total),
    );
  }

  double round(double value) {
    if (!value.isFinite) return 0;
    return (value * 1000).roundToDouble() / 1000;
  }
}
