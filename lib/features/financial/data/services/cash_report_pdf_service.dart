import 'dart:typed_data';

import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/app_pdf_localization.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/pdf/business_pdf_settings_resolver.dart';
import 'package:fatoora/core/pdf/business_pdf_widgets.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:pdf/widgets.dart' as pw;

class CashReportPdfService {
  const CashReportPdfService._();

  static Future<Uint8List> build({
    required FinancialCashSnapshot snapshot,
    required DateTime? fromDate,
    required DateTime? toDate,
    required String salesRepFilterLabel,
    bool isAdminView = true,
    String companyId = 'default_company',
    BusinessPdfConfiguration? configuration,
  }) async {
    final pdfConfiguration =
        configuration ??
        await BusinessPdfSettingsResolver.resolve(companyId: companyId);
    final assets = await AppPdfAssets.load(loadLogo: pdfConfiguration.showLogo);
    final loc = pdfConfiguration.localization;
    final document = pw.Document(
      theme: assets.theme,
      title: '${loc.t('cash_report')} ${loc.dateRange(fromDate, toDate)}',
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
          title: loc.t('cash_report'),
          subtitle: loc.dateRange(fromDate, toDate),
        ),
        footer: (context) => BusinessPdfWidgets.pageFooter(
          context: context,
          loc: loc,
          text: pdfConfiguration.pdfSettings.statementFooterText,
        ),
        build: (_) => [
          BusinessPdfWidgets.infoGrid(
            loc: loc,
            items: _summaryItems(
              loc: loc,
              snapshot: snapshot,
              fromDate: fromDate,
              toDate: toDate,
              salesRepFilterLabel: salesRepFilterLabel,
              isAdminView: isAdminView,
            ),
          ),
          pw.SizedBox(height: 16),
          BusinessPdfWidgets.table(
            loc: loc,
            headers: [
              loc.t('date'),
              loc.t('type'),
              loc.t('direction'),
              loc.t('amount'),
              loc.t('reference_number'),
              loc.t('sales_rep'),
              loc.t('notes'),
            ],
            data: snapshot.movements
                .map(
                  (movement) => [
                    loc.date(movement.date),
                    loc.enumValue(movement.effectiveType),
                    loc.t(movement.direction),
                    loc.money(movement.amount),
                    movement.effectiveReferenceNumber,
                    movement.salesRepName,
                    movement.notes,
                  ],
                )
                .toList(growable: false),
          ),
          pw.SizedBox(height: 14),
          BusinessPdfWidgets.totals(
            loc: loc,
            rows: [
              PdfInfoItem(
                loc.t('opening_balance'),
                loc.money(snapshot.openingBalance),
              ),
              PdfInfoItem(loc.t('total_in'), loc.money(snapshot.totalIn)),
              PdfInfoItem(loc.t('total_out'), loc.money(snapshot.totalOut)),
              PdfInfoItem(
                loc.t('closing_balance'),
                loc.money(snapshot.closingBalance),
                bold: true,
              ),
              if (isAdminView)
                PdfInfoItem(
                  loc.t('rep_cash_outstanding'),
                  loc.money(snapshot.repCashOutstanding),
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

  static List<PdfInfoItem> _summaryItems({
    required AppPdfLocalization loc,
    required FinancialCashSnapshot snapshot,
    required DateTime? fromDate,
    required DateTime? toDate,
    required String salesRepFilterLabel,
    required bool isAdminView,
  }) {
    return [
      PdfInfoItem(loc.t('date_range'), loc.dateRange(fromDate, toDate)),
      PdfInfoItem(loc.t('sales_rep'), salesRepFilterLabel),
      PdfInfoItem(loc.t('opening_balance'), loc.money(snapshot.openingBalance)),
      PdfInfoItem(loc.t('total_in'), loc.money(snapshot.totalIn)),
      PdfInfoItem(loc.t('total_out'), loc.money(snapshot.totalOut)),
      PdfInfoItem(
        loc.t('closing_balance'),
        loc.money(snapshot.closingBalance),
        bold: true,
      ),
      if (isAdminView)
        PdfInfoItem(
          loc.t('rep_cash_outstanding'),
          loc.money(snapshot.repCashOutstanding),
        ),
    ];
  }
}
