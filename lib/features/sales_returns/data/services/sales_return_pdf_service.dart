import 'dart:typed_data';

import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/pdf/business_pdf_settings_resolver.dart';
import 'package:fatoora/core/pdf/business_pdf_widgets.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:pdf/widgets.dart' as pw;

class SalesReturnPdfService {
  const SalesReturnPdfService._();

  static Future<Uint8List> build(
    SalesReturnModel salesReturn, {
    BusinessPdfConfiguration? configuration,
  }) async {
    final pdfConfiguration =
        configuration ??
        await BusinessPdfSettingsResolver.resolve(
          companyId: salesReturn.companyId,
        );
    final assets = await AppPdfAssets.load(loadLogo: pdfConfiguration.showLogo);
    final loc = pdfConfiguration.localization;
    final document = pw.Document(
      theme: assets.theme,
      title: '${loc.t('sales_return')} ${salesReturn.returnNumber}',
      author: pdfConfiguration.companySettings.name,
      creator: 'Fatoora',
    );
    final customer = salesReturn.customerSnapshot;

    document.addPage(
      pw.MultiPage(
        pageTheme: BusinessPdfWidgets.pageTheme(
          assets,
          textDirection: loc.textDirection,
        ),
        maxPages: 100,
        header: (_) => BusinessPdfWidgets.pageHeader(
          assets: assets,
          configuration: pdfConfiguration,
          title: loc.t('sales_return'),
          subtitle: salesReturn.returnNumber,
        ),
        footer: (context) =>
            BusinessPdfWidgets.pageFooter(context: context, loc: loc),
        build: (_) => [
          BusinessPdfWidgets.infoGrid(
            loc: loc,
            items: [
              PdfInfoItem(
                loc.t('return_number'),
                salesReturn.returnNumber,
                bold: true,
              ),
              PdfInfoItem(
                loc.t('original_invoice_number'),
                salesReturn.originalInvoiceNumber,
              ),
              PdfInfoItem(
                loc.t('return_date'),
                loc.date(salesReturn.returnDate),
              ),
              if (salesReturn.originalInvoiceDate != null)
                PdfInfoItem(
                  loc.t('invoice_date'),
                  loc.date(salesReturn.originalInvoiceDate!),
                ),
              PdfInfoItem(loc.t('customer'), customer?.name ?? ''),
              PdfInfoItem(loc.t('sales_rep'), salesReturn.salesRepName),
              PdfInfoItem(
                loc.t('refund_type'),
                loc.enumValue(salesReturn.refundType.value),
              ),
              PdfInfoItem(
                loc.t('status'),
                loc.enumValue(salesReturn.status.value),
              ),
              PdfInfoItem(
                loc.t('inventory_posted'),
                salesReturn.inventoryPosted ? loc.t('yes') : loc.t('no'),
              ),
              PdfInfoItem(
                loc.t('financial_posted'),
                salesReturn.financialPosted ? loc.t('yes') : loc.t('no'),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          BusinessPdfWidgets.table(
            loc: loc,
            headers: [
              loc.t('item'),
              loc.t('quantity'),
              loc.t('unit'),
              loc.t('unit_price'),
              loc.t('tax'),
              loc.t('total'),
            ],
            data: salesReturn.items
                .map(
                  (item) => [
                    [
                      item.itemName,
                      item.description,
                    ].where((value) => value.trim().isNotEmpty).join('\n'),
                    loc.quantity(item.returnedQuantity),
                    item.unit,
                    loc.money(item.unitPrice),
                    loc.money(item.taxAmount),
                    loc.money(item.total),
                  ],
                )
                .toList(growable: false),
          ),
          pw.SizedBox(height: 14),
          BusinessPdfWidgets.totals(
            loc: loc,
            rows: [
              PdfInfoItem(loc.t('subtotal'), loc.money(salesReturn.subtotal)),
              PdfInfoItem(loc.t('total_tax'), loc.money(salesReturn.totalTax)),
              if (salesReturn.totalDiscount > 0)
                PdfInfoItem(
                  loc.t('total_discount'),
                  loc.money(salesReturn.totalDiscount),
                ),
              PdfInfoItem(
                loc.t('grand_total'),
                loc.money(salesReturn.grandTotal),
                bold: true,
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          BusinessPdfWidgets.notes(
            loc: loc,
            title: loc.t('reason'),
            text: salesReturn.reason,
          ),
          BusinessPdfWidgets.notes(
            loc: loc,
            title: loc.t('notes'),
            text: pdfConfiguration.pdfSettings.defaultNotes,
          ),
        ],
      ),
    );
    return document.save();
  }
}
