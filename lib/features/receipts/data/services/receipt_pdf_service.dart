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
    final document = pw.Document(
      theme: assets.theme,
      title: '${loc.t('receipt')} ${receipt.receiptNumber}',
      author: pdfConfiguration.companySettings.name,
      creator: 'Fatoora',
    );
    final allocationRows = receipt.invoiceAllocationDetails.isNotEmpty
        ? receipt.invoiceAllocationDetails
              .map(
                (allocation) => [
                  allocation.invoiceNumber.isEmpty
                      ? allocation.invoiceId
                      : allocation.invoiceNumber,
                  loc.money(allocation.amount),
                ],
              )
              .toList(growable: false)
        : receipt.invoiceAllocations.entries
              .map((entry) => [entry.key, loc.money(entry.value)])
              .toList(growable: false);

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
          title: loc.t('receipt'),
          subtitle: receipt.receiptNumber,
        ),
        footer: (context) => BusinessPdfWidgets.pageFooter(
          context: context,
          loc: loc,
          text: pdfConfiguration.pdfSettings.receiptFooterText,
        ),
        build: (_) => [
          BusinessPdfWidgets.infoGrid(
            loc: loc,
            items: [
              PdfInfoItem(
                loc.t('receipt_number'),
                receipt.receiptNumber,
                bold: true,
              ),
              PdfInfoItem(loc.t('receipt_date'), loc.date(receipt.receiptDate)),
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
              if (receipt.resultingCustomerBalance != null)
                PdfInfoItem(
                  loc.t('resulting_customer_balance'),
                  loc.money(receipt.resultingCustomerBalance!),
                  bold: true,
                ),
            ],
          ),
          if (allocationRows.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            BusinessPdfWidgets.sectionTitle(loc.t('invoice_allocations')),
            BusinessPdfWidgets.table(
              loc: loc,
              headers: [loc.t('invoice_number'), loc.t('allocated_amount')],
              data: allocationRows,
            ),
          ],
          pw.SizedBox(height: 16),
          BusinessPdfWidgets.notes(
            loc: loc,
            title: loc.t('notes'),
            text: pdfConfiguration.receiptNotes(receipt.notes),
          ),
          pw.SizedBox(height: 26),
          BusinessPdfWidgets.signatures(loc),
        ],
      ),
    );
    return document.save();
  }
}
