import 'dart:math' as math;
import 'package:fatoora/core/finance/exact_decimal.dart';

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
        ? round(item.quantity)
        : 0.0;
    final unitPrice = item.unitPrice.isFinite && item.unitPrice >= 0
        ? round(item.unitPrice)
        : 0.0;
    final rawSubtotal = ExactDecimal.multiply(quantity, unitPrice);
    final discount = item.discount.isFinite
        ? round(item.discount).clamp(0, rawSubtotal).toDouble()
        : 0.0;
    final taxableAmount = round(math.max(rawSubtotal - discount, 0).toDouble());
    final taxPercent = item.taxPercent.isFinite
        ? round(item.taxPercent).clamp(0, 100).toDouble()
        : 0.0;
    final taxAmount = ExactDecimal.percentage(taxableAmount, taxPercent);
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
    final subtotal = ExactDecimal.sum(items.map((item) => item.subtotal));
    final discount = ExactDecimal.sum(items.map((item) => item.discount));
    final tax = ExactDecimal.sum(items.map((item) => item.taxAmount));
    final total = ExactDecimal.sum(items.map((item) => item.total));
    return InvoiceTotals(
      items: items,
      subtotal: round(subtotal),
      totalDiscount: round(discount),
      totalTax: round(tax),
      grandTotal: round(total),
    );
  }

  /// Shared draft/conversion validation. Confirmation recalculates again on the
  /// trusted backend; client-provided aggregate amounts are never authoritative.
  InvoiceTotals validateInvoice(List<InvoiceItemSnapshot> items) {
    if (items.isEmpty || items.length > 100) {
      throw const FormatException('Invoice requires 1 to 100 valid lines.');
    }
    final lineIds = <String>{};
    for (final item in items) {
      final validIdentity = item.lineType == InvoiceLineType.catalog
          ? (item.itemId?.trim().isNotEmpty ?? false)
          : item.isLegacyManual ||
                (item.itemId == null &&
                    item.description.trim().isNotEmpty &&
                    item.unit.trim().isNotEmpty);
      if (!validIdentity ||
          item.itemName.trim().isEmpty ||
          !hasValidQuantity(item.quantity) ||
          !hasValidUnitPrice(item.unitPrice) ||
          !hasValidDiscount(
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            discount: item.discount,
          ) ||
          !hasValidTaxPercent(item.taxPercent) ||
          (item.lineId.isNotEmpty && !lineIds.add(item.lineId))) {
        throw const FormatException('Invalid invoice line.');
      }
    }
    final totals = calculateInvoice(items);
    if (!totals.grandTotal.isFinite || totals.grandTotal <= 0) {
      throw const FormatException('Invoice total must be positive.');
    }
    return totals;
  }

  double round(double value) {
    if (!value.isFinite) return 0;
    return ExactDecimal.round(value);
  }

  bool hasValidQuantity(double value) =>
      value.isFinite && value > 0 && round(value) > 0;

  bool hasValidUnitPrice(double value) => value.isFinite && value >= 0;

  bool hasValidTaxPercent(double value) =>
      value.isFinite && value >= 0 && value <= 100;

  bool hasValidDiscount({
    required double quantity,
    required double unitPrice,
    required double discount,
  }) {
    if (!hasValidQuantity(quantity) ||
        !hasValidUnitPrice(unitPrice) ||
        !discount.isFinite ||
        discount < 0) {
      return false;
    }
    return round(discount) <=
        ExactDecimal.multiply(round(quantity), round(unitPrice));
  }

  bool hasValidLineTotal(double value) => value.isFinite && value >= 0;
}
