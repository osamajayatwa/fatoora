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
    final document = pw.Document(theme: assets.theme);

    document.addPage(
      pw.MultiPage(
        pageTheme: BusinessPdfWidgets.pageTheme(assets),
        build: (_) => [
          BusinessPdfWidgets.shell(
            assets: assets,
            configuration: pdfConfiguration,
            title: loc.t('cash_report'),
            subtitle: loc.dateRange(fromDate, toDate),
            children: [
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
                rows: isAdminView
                    ? [
                        PdfInfoItem(
                          loc.t('company_cash'),
                          loc.money(snapshot.companyCash),
                        ),
                        PdfInfoItem(
                          loc.t('rep_cash_outstanding'),
                          loc.money(snapshot.repCashOutstanding),
                        ),
                        PdfInfoItem(
                          loc.t('total_cash_position'),
                          loc.money(
                            snapshot.companyCash + snapshot.repCashOutstanding,
                          ),
                          bold: true,
                        ),
                      ]
                    : [
                        PdfInfoItem(
                          loc.t('rep_cash_to_settle'),
                          loc.money(snapshot.repCashOutstanding),
                          bold: true,
                        ),
                        PdfInfoItem(
                          loc.t('total_in'),
                          loc.money(snapshot.totalIn),
                        ),
                        PdfInfoItem(
                          loc.t('total_out'),
                          loc.money(snapshot.totalOut),
                        ),
                      ],
              ),
              BusinessPdfWidgets.notes(
                loc: loc,
                title: loc.t('notes'),
                text: pdfConfiguration.pdfSettings.defaultNotes,
              ),
              BusinessPdfWidgets.footer(
                loc: loc,
                text: pdfConfiguration.pdfSettings.statementFooterText,
              ),
            ],
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
    if (isAdminView) {
      return [
        PdfInfoItem(loc.t('date_range'), loc.dateRange(fromDate, toDate)),
        PdfInfoItem(loc.t('sales_rep'), salesRepFilterLabel),
        PdfInfoItem(
          loc.t('company_cash'),
          loc.money(snapshot.companyCash),
          bold: true,
        ),
        PdfInfoItem(
          loc.t('rep_cash_outstanding'),
          loc.money(snapshot.repCashOutstanding),
        ),
        PdfInfoItem(
          loc.t('total_cash_position'),
          loc.money(snapshot.companyCash + snapshot.repCashOutstanding),
          bold: true,
        ),
      ];
    }
    return [
      PdfInfoItem(loc.t('date_range'), loc.dateRange(fromDate, toDate)),
      PdfInfoItem(loc.t('sales_rep'), salesRepFilterLabel),
      PdfInfoItem(
        loc.t('rep_cash_to_settle'),
        loc.money(snapshot.repCashOutstanding),
        bold: true,
      ),
      PdfInfoItem(loc.t('total_in'), loc.money(snapshot.totalIn)),
      PdfInfoItem(loc.t('total_out'), loc.money(snapshot.totalOut)),
    ];
  }
}
