import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/auth/utils/auth_session.dart';
import 'package:fatoora/features/financial/controllers/financial_error_mapper.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:fatoora/features/financial/data/services/cash_report_pdf_service.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';

class CashMovementsController extends GetxController {
  CashMovementsController({
    required FinancialRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final FinancialRepository _repository;
  final MyServices _myServices;

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
    statusRequest = StatusRequest.loading;
    update();
    try {
      snapshot = await _repository.fetchCash(
        companyId: companyId,
        fromDate: fromDate,
        toDate: toDate,
      );
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = FinancialErrorMapper.status(error);
      loadErrorMessageKey = FinancialErrorMapper.messageKey(error);
    }
    if (!isClosed) update();
  }

  Future<void> refreshCash() => loadCash();

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
      await Printing.layoutPdf(
        name: 'cash-report.pdf',
        onLayout: (_) => CashReportPdfService.build(
          snapshot: snapshot,
          fromDate: fromDate,
          toDate: toDate,
          salesRepFilterLabel: filterLabel,
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
