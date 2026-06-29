import 'dart:typed_data';

import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/controllers/customer_error_mapper.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:fatoora/features/customers/data/services/customer_statement_pdf_service.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';

class CustomerStatementController extends GetxController {
  CustomerStatementController({
    required CustomerRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final CustomerRepository _repository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'customers_statement_load_error';
  String companyId = AuthRepository.defaultCompanyId;
  String customerId = '';
  DateTime? fromDate;
  DateTime? toDate;
  CustomerModel? customer;
  List<CustomerTransactionModel> transactions = const [];
  bool isPrinting = false;

  double openingBalance = 0;
  double totalDebit = 0;
  double totalCredit = 0;
  double finalBalance = 0;

  @override
  void onReady() {
    super.onReady();
    loadStatement();
  }

  Future<void> loadStatement() async {
    final args = Get.arguments;
    if (args is Map) {
      companyId =
          (args['companyId'] as String?) ??
          _myServices.sharedPreferences.getString('companyId') ??
          AuthRepository.defaultCompanyId;
      customerId = (args['customerId'] as String?)?.trim() ?? '';
    }
    if (customerId.isEmpty) {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'customers_not_found';
      update();
      return;
    }
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'customers_statement_load_error';
    update();
    try {
      customer = await _repository.getCustomer(
        companyId: companyId,
        customerId: customerId,
      );
      final statement = await _repository.fetchStatement(
        companyId: companyId,
        customerId: customerId,
        fromDate: fromDate,
        toDate: toDate,
      );
      transactions = statement.transactions;
      openingBalance = statement.openingBalance;
      totalDebit = statement.totalDebit;
      totalCredit = statement.totalCredit;
      finalBalance = statement.closingBalance;
      if (fromDate == null && toDate == null && transactions.isEmpty) {
        openingBalance = customer!.currentBalance;
        finalBalance = customer!.currentBalance;
      }
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = CustomerErrorMapper.status(error);
      loadErrorMessageKey = CustomerErrorMapper.messageKey(
        error,
        fallback: 'customers_statement_load_error',
      );
      _showError(loadErrorMessageKey);
    }
    if (!isClosed) update();
  }

  void setDateRange(DateTime? from, DateTime? to) {
    fromDate = from;
    toDate = to;
    loadStatement();
  }

  void clearDateRange() {
    fromDate = null;
    toDate = null;
    loadStatement();
  }

  Future<void> printStatement() async {
    final current = customer;
    if (current == null || isPrinting) return;
    isPrinting = true;
    update();
    try {
      await Printing.layoutPdf(
        name: _pdfFilename(current),
        onLayout: (_) => _buildPdf(current),
      );
    } catch (_) {
      _showError('customers_statement_pdf_error');
    } finally {
      isPrinting = false;
      if (!isClosed) update();
    }
  }

  Future<void> exportStatementPdf() async {
    final current = customer;
    if (current == null || isPrinting) return;
    isPrinting = true;
    update();
    try {
      await Printing.sharePdf(
        bytes: await _buildPdf(current),
        filename: _pdfFilename(current),
      );
    } catch (_) {
      _showError('customers_statement_pdf_error');
    } finally {
      isPrinting = false;
      if (!isClosed) update();
    }
  }

  Future<Uint8List> _buildPdf(CustomerModel current) {
    return CustomerStatementPdfService.build(
      customer: current,
      transactions: transactions,
      fromDate: fromDate,
      toDate: toDate,
      openingBalance: openingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
    );
  }

  String _pdfFilename(CustomerModel current) {
    final safeName = current.name
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '${safeName.isEmpty ? 'customer' : safeName}-statement.pdf';
  }

  Future<void> requestBack() async {
    Get.back<void>();
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'customers'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }
}
