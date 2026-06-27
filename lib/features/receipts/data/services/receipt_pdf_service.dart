import 'dart:typed_data';

import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/pdf/business_pdf_settings_resolver.dart';
import 'package:fatoora/core/pdf/business_pdf_widgets.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:pdf/widgets.dart' as pw;

class ReceiptPdfService {
  const ReceiptPdfService._();

  static Future<Uint8List> build(
    ReceiptModel receipt, {
    BusinessPdfConfiguration? configuration,
  }) async {
    final pdfConfiguration =
        configuration ??
        await BusinessPdfSettingsResolver.resolve(
          companyId: receipt.companyId,
          includeUserPreferences: true,
        );
    final assets = await AppPdfAssets.load(loadLogo: pdfConfiguration.showLogo);
    final loc = pdfConfiguration.localization;
    final document = pw.Document(theme: assets.theme);

    document.addPage(
      pw.MultiPage(
        pageTheme: BusinessPdfWidgets.pageTheme(assets),
        build: (_) => [
          BusinessPdfWidgets.shell(
            assets: assets,
            configuration: pdfConfiguration,
            title: loc.t('receipt'),
            subtitle: receipt.receiptNumber,
            children: [
              BusinessPdfWidgets.infoGrid(
                loc: loc,
                items: [
                  PdfInfoItem(
                    loc.t('receipt_number'),
                    receipt.receiptNumber,
                    bold: true,
                  ),
                  PdfInfoItem(
                    loc.t('receipt_date'),
                    loc.date(receipt.receiptDate),
                  ),
                  PdfInfoItem(loc.t('customer'), receipt.customerSnapshot.name),
                  PdfInfoItem(loc.t('phone'), receipt.customerSnapshot.phone),
                  PdfInfoItem(
                    loc.t('amount'),
                    loc.money(receipt.amount),
                    bold: true,
                  ),
                  PdfInfoItem(
                    loc.t('payment_method'),
                    loc.enumValue('payment_method_${receipt.paymentMethod}'),
                  ),
                  PdfInfoItem(loc.t('sales_rep'), receipt.salesRepName),
                ],
              ),
              pw.SizedBox(height: 16),
              BusinessPdfWidgets.notes(
                loc: loc,
                title: loc.t('notes'),
                text: pdfConfiguration.receiptNotes(receipt.notes),
              ),
              pw.SizedBox(height: 26),
              BusinessPdfWidgets.signatures(loc),
              BusinessPdfWidgets.footer(
                loc: loc,
                text: pdfConfiguration.pdfSettings.receiptFooterText,
              ),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }
}
