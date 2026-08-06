import 'dart:typed_data';

import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/pdf/business_pdf_settings_resolver.dart';
import 'package:fatoora/core/pdf/business_pdf_widgets.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:pdf/widgets.dart' as pw;

class CustomerStatementPdfService {
  const CustomerStatementPdfService._();

  static Future<Uint8List> build({
    required CustomerModel customer,
    required List<CustomerTransactionModel> transactions,
    required DateTime? fromDate,
    required DateTime? toDate,
    required double openingBalance,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    BusinessPdfConfiguration? configuration,
  }) async {
    final pdfConfiguration =
        configuration ??
        await BusinessPdfSettingsResolver.resolve(
          companyId: customer.companyId,
        );
    final assets = await AppPdfAssets.load(loadLogo: pdfConfiguration.showLogo);
    final loc = pdfConfiguration.localization;
    final document = pw.Document(
      theme: assets.theme,
      title: '${loc.t('customer_statement')} ${customer.name}',
      author: pdfConfiguration.companySettings.name,
      creator: 'Fatoora',
    );

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
          title: loc.t('customer_statement'),
          subtitle: customer.name,
        ),
        footer: (context) => BusinessPdfWidgets.pageFooter(
          context: context,
          loc: loc,
          text: pdfConfiguration.pdfSettings.statementFooterText,
        ),
        build: (_) => [
          BusinessPdfWidgets.infoGrid(
            loc: loc,
            items: [
              PdfInfoItem(loc.t('customer'), customer.name, bold: true),
              PdfInfoItem(loc.t('phone'), customer.phone),
              PdfInfoItem(loc.t('address'), customer.addressText),
              PdfInfoItem(loc.t('date_range'), loc.dateRange(fromDate, toDate)),
              PdfInfoItem(loc.t('opening_balance'), loc.money(openingBalance)),
              PdfInfoItem(
                loc.t('final_balance'),
                loc.money(finalBalance),
                bold: true,
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          BusinessPdfWidgets.table(
            loc: loc,
            headers: [
              loc.t('date'),
              loc.t('transaction_type'),
              loc.t('reference_number'),
              loc.t('description'),
              loc.t('debit'),
              loc.t('credit'),
              loc.t('running_balance'),
            ],
            data: transactions
                .map(
                  (transaction) => [
                    loc.date(transaction.transactionDate),
                    loc.enumValue(transaction.transactionType),
                    transaction.sourceNumber,
                    transaction.notes,
                    loc.money(transaction.debitAmount),
                    loc.money(transaction.creditAmount),
                    loc.money(transaction.balanceAfter),
                  ],
                )
                .toList(growable: false),
          ),
          pw.SizedBox(height: 14),
          BusinessPdfWidgets.totals(
            loc: loc,
            rows: [
              PdfInfoItem(loc.t('opening_balance'), loc.money(openingBalance)),
              PdfInfoItem(loc.t('total_debit'), loc.money(totalDebit)),
              PdfInfoItem(loc.t('total_credit'), loc.money(totalCredit)),
              PdfInfoItem(
                loc.t('final_balance'),
                loc.money(finalBalance),
                bold: true,
              ),
            ],
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
