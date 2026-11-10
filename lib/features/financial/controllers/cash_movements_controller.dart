import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/pdf/business_pdf_settings_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/auth/utils/auth_session.dart';
import 'package:fatoora/features/financial/controllers/financial_error_mapper.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:fatoora/features/financial/data/services/cash_report_pdf_service.dart';
import 'package:fatoora/features/financial/data/services/settlement_details_fixtures.dart';
import 'package:fatoora/features/financial/data/models/settlement_details.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';

class CashMovementsController extends GetxController {
  CashMovementsController({
    required FinancialRepository repository,
    required MyServices myServices,
    SettlementDetailsFixtures? settlementDetailsFixtures,
    SettlementDetailsSource Function(
      String representativeId,
      String settlementId,
    )?
    settlementSourceFactory,
  }) : _repository = repository,
       _myServices = myServices,
       _settlementDetailsFixtures = settlementDetailsFixtures,
       _settlementSourceFactory = settlementSourceFactory;

  final FinancialRepository _repository;
  final MyServices _myServices;
  final SettlementDetailsFixtures? _settlementDetailsFixtures;
  final SettlementDetailsSource Function(String, String)?
  _settlementSourceFactory;
  final Map<String, SettlementDetailsSource> _settlementSources = {};

  SettlementDetailsSource? settlementSourceFor(
    String settlementId,
    String representativeId,
  ) {
    const stagingPilot =
        bool.fromEnvironment('FATOORA_SETTLEMENT_STAGING_PILOT') &&
        String.fromEnvironment('FATOORA_ENV') == 'staging';
    if (kReleaseMode && (!stagingPilot || _settlementSourceFactory != null) ||
        !isAdmin ||
        settlementId.isEmpty ||
        representativeId.isEmpty) {
      return null;
    }
    final fixture = settlementDetailsFor(settlementId);
    if (fixture != null && fixture.representativeId == representativeId) {
      return fixture;
    }
    if (_settlementSourceFactory == null &&
        (!(const bool.fromEnvironment('FATOORA_SETTLEMENT_TRANSPORT_TEST') ||
                stagingPilot) ||
            !_repository.settlementTransportEnabled)) {
      return null;
    }
    final key = '$companyId/$representativeId/$settlementId';
    if (_settlementSources.containsKey(key)) return _settlementSources[key];
    if (_settlementSources.length >= 4) {
      _settlementSources.remove(_settlementSources.keys.first);
    }
    final source =
        _settlementSourceFactory?.call(representativeId, settlementId) ??
        _repository.settlementDetailsSource(
          companyId: companyId,
          representativeId: representativeId,
          settlementId: settlementId,
        );
    if (source.companyId != companyId ||
        source.representativeId != representativeId ||
        source.settlementId != settlementId) {
      return null;
    }
    return _settlementSources[key] = source;
  }

  Future<void> printSettlementDetails(SettlementDetailsReport report) async {
    if (report.origin == SettlementDetailsOrigin.syntheticFixture) {
      return printSettlementFixture(report);
    }
    final source = settlementSourceFor(
      report.header.settlementId ?? '',
      report.header.representativeId,
    );
    if (source == null ||
        source.origin != report.origin ||
        source.companyId != companyId ||
        isPrinting) {
      return;
    }
    isPrinting = true;
    update();
    try {
      await Printing.layoutPdf(
        name: 'settlement-evidence.pdf',
        onLayout: (_) async {
          final configuration = await BusinessPdfSettingsResolver.resolve(
            companyId: companyId,
          );
          final bytes = await CashReportPdfService.buildSettlementDetails(
            details: report,
            configuration: configuration,
            representativeLabel: source.representativeLabel,
            settlementLabel: source.settlementLabel,
          );
          // Validate current authority/evidence after potentially slow rendering,
          // immediately before handing bytes to the native print/PDF platform.
          await source.authorizePdf(report);
          source.requirePdfPermission(report);
          return bytes;
        },
      );
    } catch (_) {
      Get.snackbar('financial_cash'.tr, 'cash_report_pdf_error'.tr);
    } finally {
      isPrinting = false;
      if (!isClosed) update();
    }
  }

  /// No production binding supplies fixtures; release builds reject even an
  /// explicitly injected fixture. Existing live cash paths remain untouched.
  SettlementDetailsFixtures? settlementDetailsFor(String settlementId) {
    final fixture = _settlementDetailsFixtures;
    return !kReleaseMode &&
            isAdmin &&
            fixture != null &&
            companyId == fixture.companyId &&
            settlementId == fixture.settlementId
        ? fixture
        : null;
  }

  Future<void> printSettlementFixture(SettlementDetailsReport report) async {
    final fixture = settlementDetailsFor(report.header.settlementId ?? '');
    if (fixture == null ||
        report.header.companyId != companyId ||
        report.header.representativeId != fixture.representativeId) {
      return;
    }
    if (isPrinting) return;
    isPrinting = true;
    update();
    try {
      await Printing.layoutPdf(
        name: 'synthetic-settlement-preview.pdf',
        onLayout: (_) => CashReportPdfService.buildSettlementDetails(
          details: report,
          representativeLabel: fixture.representativeLabel,
          settlementLabel: fixture.settlementLabel,
          configuration: CashReportPdfService.settlementFixtureConfiguration(
            Get.locale?.languageCode ?? 'en',
          ),
        ),
      );
    } catch (_) {
      Get.snackbar('financial_cash'.tr, 'cash_report_pdf_error'.tr);
    } finally {
      isPrinting = false;
      if (!isClosed) update();
    }
  }

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'financial_load_error';
  DateTime? fromDate;
  DateTime? toDate;
  FinancialCashSnapshot snapshot = const FinancialCashSnapshot(
    movements: [],
    cashInHand: 0,
    totalIn: 0,
    totalOut: 0,
    cashBySalesRep: [],
  );
  bool isSavingSettlement = false;
  bool isPrinting = false;
  bool isLoadingMore = false;
  String? loadMoreErrorMessageKey;
  bool hasMore = false;
  FirestorePageCursor? _cursor;
  int _loadGeneration = 0;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  bool get isAdmin =>
      _myServices.sharedPreferences.getString('role') ==
      AuthRepository.adminRole;

  @override
  void onReady() {
    super.onReady();
    loadCash();
  }

  Future<void> loadCash() async {
    final generation = ++_loadGeneration;
    statusRequest = StatusRequest.loading;
    loadMoreErrorMessageKey = null;
    _cursor = null;
    hasMore = false;
    update();
    try {
      final page = await _repository.fetchCashPage(
        companyId: companyId,
        fromDate: fromDate,
        toDate: toDate,
      );
      if (generation != _loadGeneration) return;
      snapshot = page.snapshot;
      _cursor = page.cursor;
      hasMore = page.hasMore;
      statusRequest = StatusRequest.success;
    } catch (error) {
      if (generation != _loadGeneration) return;
      statusRequest = FinancialErrorMapper.status(error);
      loadErrorMessageKey = FinancialErrorMapper.messageKey(error);
    }
    if (!isClosed) update();
  }

  Future<void> refreshCash() => loadCash();

  Future<void> loadMore() async {
    if (isLoadingMore || !hasMore || _cursor == null) return;
    isLoadingMore = true;
    loadMoreErrorMessageKey = null;
    final generation = _loadGeneration;
    update();
    try {
      final page = await _repository.fetchCashMovementDetailsPage(
        companyId: companyId,
        fromDate: fromDate,
        toDate: toDate,
        after: _cursor,
      );
      if (generation != _loadGeneration) return;
      snapshot = FinancialCashSnapshot(
        movements: {
          for (final movement in [...snapshot.movements, ...page.items])
            movement.id: movement,
        }.values.toList(growable: false),
        openingBalance: snapshot.openingBalance,
        closingBalance: snapshot.closingBalance,
        cashInHand: snapshot.cashInHand,
        companyCash: snapshot.companyCash,
        repCashOutstanding: snapshot.repCashOutstanding,
        totalIn: snapshot.totalIn,
        totalOut: snapshot.totalOut,
        cashBySalesRep: snapshot.cashBySalesRep,
        repCashOutstandingBySalesRep: snapshot.repCashOutstandingBySalesRep,
        reportedValues: snapshot.reportedValues,
      );
      _cursor = page.cursor;
      hasMore = page.hasMore;
    } catch (error) {
      if (generation != _loadGeneration) return;
      loadMoreErrorMessageKey = FinancialErrorMapper.messageKey(error);
    } finally {
      isLoadingMore = false;
      if (!isClosed) update();
    }
  }

  void setDateRange(DateTime? from, DateTime? to) {
    fromDate = from;
    toDate = to;
    loadCash();
  }

  void clearDateRange() {
    fromDate = null;
    toDate = null;
    loadCash();
  }

  Future<void> recordSettlement({
    required FinancialRepAmount rep,
    required double amount,
    required String notes,
  }) async {
    if (isSavingSettlement) return;
    isSavingSettlement = true;
    update();
    try {
      await _repository.recordCashSettlement(
        companyId: companyId,
        salesRepId: rep.salesRepId,
        salesRepName: rep.salesRepName,
        amount: amount,
        settlementDate: DateTime.now(),
        notes: notes,
      );
      Get.snackbar(
        'financial_cash_settlement'.tr,
        'financial_cash_settlement_saved'.tr,
      );
      await loadCash();
    } catch (error) {
      Get.snackbar(
        'financial_cash_settlement'.tr,
        FinancialErrorMapper.messageKey(error).tr,
      );
    } finally {
      isSavingSettlement = false;
      if (!isClosed) update();
    }
  }

  Future<void> printCashReport() async {
    if (isPrinting) return;
    isPrinting = true;
    update();
    try {
      final filterLabel = isAdmin
          ? 'all'.tr
          : AuthSession.cachedDisplayName(_myServices);
      final exportSnapshot = await _repository.fetchCash(
        companyId: companyId,
        fromDate: fromDate,
        toDate: toDate,
      );
      await Printing.layoutPdf(
        name: 'cash-report.pdf',
        onLayout: (_) => CashReportPdfService.build(
          snapshot: exportSnapshot,
          fromDate: fromDate,
          toDate: toDate,
          salesRepFilterLabel: filterLabel,
          isAdminView: isAdmin,
          companyId: companyId,
        ),
      );
    } catch (_) {
      Get.snackbar(
        'financial_cash'.tr,
        'cash_report_pdf_error'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.error,
        colorText: AppColor.surface,
      );
    } finally {
      isPrinting = false;
      if (!isClosed) update();
    }
  }
}
