import 'dart:typed_data';

import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/app_pdf_localization.dart';
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
  }) async {
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
            title: loc.t('cash_report'),
            subtitle: loc.dateRange(fromDate, toDate),
            children: [
              BusinessPdfWidgets.infoGrid(
                loc: loc,
                items: [
                  PdfInfoItem(
                    loc.t('date_range'),
                    loc.dateRange(fromDate, toDate),
                  ),
                  PdfInfoItem(loc.t('sales_rep'), salesRepFilterLabel),
                  PdfInfoItem(
                    loc.t('cash_in_hand'),
                    loc.money(snapshot.cashInHand),
                    bold: true,
                  ),
                  PdfInfoItem(loc.t('total_in'), loc.money(snapshot.totalIn)),
                  PdfInfoItem(loc.t('total_out'), loc.money(snapshot.totalOut)),
                  PdfInfoItem(
                    loc.t('final_balance'),
                    loc.money(snapshot.cashInHand),
                    bold: true,
                  ),
                ],
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
                  PdfInfoItem(loc.t('total_in'), loc.money(snapshot.totalIn)),
                  PdfInfoItem(loc.t('total_out'), loc.money(snapshot.totalOut)),
                  PdfInfoItem(
                    loc.t('final_balance'),
                    loc.money(snapshot.cashInHand),
                    bold: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }
}
