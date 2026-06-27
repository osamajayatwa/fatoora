import 'dart:typed_data';

import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/app_pdf_localization.dart';
import 'package:fatoora/core/pdf/business_pdf_widgets.dart';
import 'package:fatoora/features/quotations/data/models/quotation_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_status.dart';
import 'package:pdf/widgets.dart' as pw;

class QuotationPdfService {
  const QuotationPdfService._();

  static Future<Uint8List> build(QuotationModel quotation) async {
    final assets = await AppPdfAssets.load();
    final loc = AppPdfLocalization.current();
    final document = pw.Document(theme: assets.theme);
    final customer = quotation.customerSnapshot;

    document.addPage(
      pw.MultiPage(
        pageTheme: BusinessPdfWidgets.pageTheme(assets),
        build: (_) => [
          BusinessPdfWidgets.shell(
            assets: assets,
            loc: loc,
            title: loc.t('quotation'),
            subtitle: quotation.quotationNumber,
            children: [
              BusinessPdfWidgets.infoGrid(
                loc: loc,
                items: [
                  PdfInfoItem(
                    loc.t('quotation_number'),
                    quotation.quotationNumber,
                    bold: true,
                  ),
                  PdfInfoItem(
                    loc.t('quotation_date'),
                    loc.date(quotation.quotationDate),
                  ),
                  PdfInfoItem(
                    loc.t('valid_until'),
                    loc.date(quotation.validUntil),
                  ),
                  PdfInfoItem(loc.t('customer'), customer?.name ?? ''),
                  PdfInfoItem(loc.t('phone'), customer?.phone ?? ''),
                  PdfInfoItem(loc.t('sales_rep'), quotation.salesRepName),
                  PdfInfoItem(
                    loc.t('quotation_status'),
                    loc.enumValue(quotation.status.value),
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
                  loc.t('discount'),
                  loc.t('tax'),
                  loc.t('total'),
                ],
                data: quotation.items
                    .map(
                      (item) => [
                        item.itemName,
                        loc.quantity(item.quantity),
                        item.unit,
                        loc.money(item.unitPrice),
                        loc.money(item.discount),
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
                  PdfInfoItem(loc.t('subtotal'), loc.money(quotation.subtotal)),
                  PdfInfoItem(
                    loc.t('total_discount'),
                    loc.money(quotation.totalDiscount),
                  ),
                  PdfInfoItem(
                    loc.t('total_tax'),
                    loc.money(quotation.totalTax),
                  ),
                  PdfInfoItem(
                    loc.t('grand_total'),
                    loc.money(quotation.grandTotal),
                    bold: true,
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              BusinessPdfWidgets.notes(
                loc: loc,
                title: loc.t('terms'),
                text: quotation.terms,
              ),
              pw.SizedBox(height: 8),
              BusinessPdfWidgets.notes(
                loc: loc,
                title: loc.t('notes'),
                text: quotation.notes,
              ),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }
}
