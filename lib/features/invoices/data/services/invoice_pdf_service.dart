import 'dart:typed_data';

import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/pdf/business_pdf_settings_resolver.dart';
import 'package:fatoora/core/pdf/business_pdf_widgets.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoicePdfService {
  const InvoicePdfService._();

  static Future<Uint8List> build(
    InvoiceModel invoice, {
    BusinessPdfConfiguration? configuration,
  }) async {
    final pdfConfiguration =
        configuration ??
        await BusinessPdfSettingsResolver.resolve(
          companyId: invoice.companyId,
          includeUserPreferences: true,
        );
    final assets = await AppPdfAssets.load(loadLogo: pdfConfiguration.showLogo);
    final loc = pdfConfiguration.localization;
    final customer = invoice.customerSnapshot;
    final document = pw.Document(theme: assets.theme);
    final qrCodeData = invoice.isElectronic
        ? invoice.government?.qrCode.trim()
        : null;
    final showQrCode = qrCodeData != null && qrCodeData.isNotEmpty;

    document.addPage(
      pw.MultiPage(
        pageTheme: BusinessPdfWidgets.pageTheme(assets),
        build: (_) => [
          BusinessPdfWidgets.shell(
            assets: assets,
            configuration: pdfConfiguration,
            title: loc.t(
              invoice.isElectronic ? 'tax_invoice' : 'sales_invoice',
            ),
            subtitle: invoice.invoiceNumber,
            children: [
              BusinessPdfWidgets.infoGrid(
                loc: loc,
                items: [
                  PdfInfoItem(
                    loc.t('invoice_number'),
                    invoice.invoiceNumber,
                    bold: true,
                  ),
                  PdfInfoItem(
                    loc.t('invoice_date'),
                    loc.date(invoice.invoiceDate),
                  ),
                  PdfInfoItem(loc.t('due_date'), loc.date(invoice.dueDate)),
                  PdfInfoItem(
                    loc.t('invoice_status'),
                    loc.enumValue(invoice.invoiceStatus.value),
                  ),
                  PdfInfoItem(
                    loc.t('payment_type'),
                    loc.enumValue(invoice.paymentType.value),
                  ),
                  PdfInfoItem(
                    loc.t('payment_status'),
                    loc.enumValue(invoice.paymentStatus.value),
                  ),
                  PdfInfoItem(loc.t('sales_rep'), invoice.salesRepName),
                ],
              ),
              pw.SizedBox(height: 16),
              BusinessPdfWidgets.sectionTitle(loc.t('customer_info')),
              BusinessPdfWidgets.infoGrid(
                loc: loc,
                items: [
                  PdfInfoItem(loc.t('customer'), customer?.name ?? ''),
                  PdfInfoItem(loc.t('phone'), customer?.phone ?? ''),
                  PdfInfoItem(loc.t('address'), customer?.address ?? ''),
                  PdfInfoItem(loc.t('city'), customer?.city ?? ''),
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
                  loc.t('line_total'),
                ],
                data: invoice.items
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
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (showQrCode) ...[
                    BusinessPdfWidgets.qrCode(qrCodeData),
                    pw.Spacer(),
                  ],
                  BusinessPdfWidgets.totals(
                    loc: loc,
                    rows: [
                      PdfInfoItem(
                        loc.t('subtotal'),
                        loc.money(invoice.subtotal),
                      ),
                      PdfInfoItem(
                        loc.t('total_discount'),
                        loc.money(invoice.totalDiscount),
                      ),
                      PdfInfoItem(
                        loc.t('total_tax'),
                        loc.money(invoice.totalTax),
                      ),
                      PdfInfoItem(
                        loc.t('grand_total'),
                        loc.money(invoice.grandTotal),
                        bold: true,
                      ),
                      PdfInfoItem(
                        loc.t('paid_amount'),
                        loc.money(invoice.paidAmount),
                      ),
                      PdfInfoItem(
                        loc.t('remaining_amount'),
                        loc.money(invoice.remainingAmount),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              BusinessPdfWidgets.notes(
                loc: loc,
                title: loc.t('notes'),
                text: pdfConfiguration.invoiceNotes(invoice.notes),
              ),
              BusinessPdfWidgets.footer(
                loc: loc,
                text: pdfConfiguration.pdfSettings.invoiceFooterText,
              ),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }
}
