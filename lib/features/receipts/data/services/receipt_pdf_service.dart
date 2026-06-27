import 'dart:typed_data';

import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/app_pdf_localization.dart';
import 'package:fatoora/core/pdf/business_pdf_widgets.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:pdf/widgets.dart' as pw;

class ReceiptPdfService {
  const ReceiptPdfService._();

  static Future<Uint8List> build(ReceiptModel receipt) async {
    final assets = await AppPdfAssets.load();
    final loc = AppPdfLocalization.current();
    final document = pw.Document(theme: assets.theme);

    document.addPage(
      pw.MultiPage(
        pageTheme: BusinessPdfWidgets.pageTheme(assets),
        build: (_) => [
          BusinessPdfWidgets.shell(
            assets: assets,
            loc: loc,
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
                text: receipt.notes,
              ),
              pw.SizedBox(height: 26),
              BusinessPdfWidgets.signatures(loc),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }
}
