import 'dart:typed_data';

import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/app_pdf_localization.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/pdf/business_pdf_settings_resolver.dart';
import 'package:fatoora/core/pdf/business_pdf_widgets.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:fatoora/features/financial/view/widgets/cash_movement_presentation.dart';
import 'package:fatoora/core/pdf/app_pdf_direction.dart';

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
        maxPages: 100 + snapshot.movements.length * 2,
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
          pw.SizedBox(height: 8),
          AppPdfDirection.text(
            loc.t('cash_scope_hint'),
            fallbackDirection: loc.textDirection,
            style: const pw.TextStyle(fontSize: 8),
          ),
          AppPdfDirection.text(
            loc.t('cash_balance_hint'),
            fallbackDirection: loc.textDirection,
            style: const pw.TextStyle(fontSize: 8),
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
              loc.t('cash_account'),
            ],
            data: snapshot.movements
                .map(
                  (movement) => [
                    movement.date == null
                        ? loc.t('cash_unavailable')
                        : loc.date(movement.date!),
                    cashTypeText(movement, loc.t),
                    cashDirectionText(movement, loc.t),
                    cashMoneyText(
                      movement.amountUnits,
                      t: loc.t,
                      arabic: loc.isArabic,
                    ),
                    movement.effectiveReferenceNumber.isEmpty
                        ? loc.t('cash_unavailable')
                        : movement.effectiveReferenceNumber,
                    cashAccountText(movement, loc.t),
                  ],
                )
                .toList(growable: false),
          ),
          pw.SizedBox(height: 14),
          for (final movement in snapshot.movements)
            ..._movementDetails(movement, loc),
          pw.SizedBox(height: 14),
          BusinessPdfWidgets.infoGrid(
            loc: loc,
            items: [
              PdfInfoItem(
                loc.t(isAdminView ? 'cash_company_opening' : 'opening_balance'),
                cashMoneyText(
                  snapshot.units('openingBalance'),
                  t: loc.t,
                  arabic: loc.isArabic,
                ),
              ),
              PdfInfoItem(
                loc.t(isAdminView ? 'cash_all_accounts_in' : 'total_in'),
                cashMoneyText(
                  snapshot.units('totalIn'),
                  t: loc.t,
                  arabic: loc.isArabic,
                ),
              ),
              PdfInfoItem(
                loc.t(isAdminView ? 'cash_all_accounts_out' : 'total_out'),
                cashMoneyText(
                  snapshot.units('totalOut'),
                  t: loc.t,
                  arabic: loc.isArabic,
                ),
              ),
              PdfInfoItem(
                loc.t(isAdminView ? 'cash_company_closing' : 'closing_balance'),
                cashMoneyText(
                  snapshot.units('closingBalance'),
                  t: loc.t,
                  arabic: loc.isArabic,
                ),
                bold: true,
              ),
              if (isAdminView)
                PdfInfoItem(
                  loc.t('rep_cash_outstanding'),
                  cashMoneyText(
                    snapshot.units('repCashOutstanding'),
                    t: loc.t,
                    arabic: loc.isArabic,
                  ),
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

  static List<pw.Widget> _movementDetails(
    CashMovementModel movement,
    AppPdfLocalization loc,
  ) {
    final fields = cashMovementDetails(
      movement,
      t: loc.t,
      timestamp: (date) => date.toIso8601String(),
      arabic: loc.isArabic,
    );
    final missing = fields
        .where((field) => !field.available)
        .map((field) => loc.t(field.key))
        .join(', ');
    return [
      pw.SizedBox(height: 12),
      AppPdfDirection.text(
        '${loc.t('cash_details')} - ${movement.id}',
        fallbackDirection: loc.textDirection,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      if (movement.hasTraceGaps)
        AppPdfDirection.text(
          loc.t('cash_trace_gap'),
          fallbackDirection: loc.textDirection,
          style: const pw.TextStyle(fontSize: 8),
        ),
      for (final field in fields.where((field) => field.available)) ...[
        // Labels and values have independent directions so RTL cannot reorder
        // timestamps, signed amounts or source identifiers. Blocks can paginate.
        AppPdfDirection.text(
          '${loc.t(field.key)}:',
          fallbackDirection: loc.textDirection,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        field.forceLtr
            ? pw.Text(
                field.value,
                textDirection: pw.TextDirection.ltr,
                style: const pw.TextStyle(fontSize: 8),
              )
            : AppPdfDirection.text(
                field.value,
                fallbackDirection: loc.textDirection,
                style: const pw.TextStyle(fontSize: 8),
              ),
        pw.SizedBox(height: 2),
      ],
      if (missing.isNotEmpty)
        AppPdfDirection.text(
          '${loc.t('cash_missing_fields')}: $missing',
          fallbackDirection: loc.textDirection,
          style: const pw.TextStyle(fontSize: 7),
        ),
    ];
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
      PdfInfoItem(
        loc.t(isAdminView ? 'cash_company_opening' : 'opening_balance'),
        cashMoneyText(
          snapshot.units('openingBalance'),
          t: loc.t,
          arabic: loc.isArabic,
        ),
      ),
      PdfInfoItem(
        loc.t(isAdminView ? 'cash_all_accounts_in' : 'total_in'),
        cashMoneyText(
          snapshot.units('totalIn'),
          t: loc.t,
          arabic: loc.isArabic,
        ),
      ),
      PdfInfoItem(
        loc.t(isAdminView ? 'cash_all_accounts_out' : 'total_out'),
        cashMoneyText(
          snapshot.units('totalOut'),
          t: loc.t,
          arabic: loc.isArabic,
        ),
      ),
      PdfInfoItem(
        loc.t(isAdminView ? 'cash_company_closing' : 'closing_balance'),
        cashMoneyText(
          snapshot.units('closingBalance'),
          t: loc.t,
          arabic: loc.isArabic,
        ),
        bold: true,
      ),
      if (isAdminView)
        PdfInfoItem(
          loc.t('rep_cash_outstanding'),
          cashMoneyText(
            snapshot.units('repCashOutstanding'),
            t: loc.t,
            arabic: loc.isArabic,
          ),
        ),
    ];
  }
}
