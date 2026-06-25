import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/constants/imageassests.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/controllers/customer_error_mapper.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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

  double get totalDebit => transactions.fold<double>(
    0,
    (sum, transaction) => sum + transaction.debitAmount,
  );
  double get totalCredit => transactions.fold<double>(
    0,
    (sum, transaction) => sum + transaction.creditAmount,
  );
  double get finalBalance => transactions.isEmpty
      ? (customer?.currentBalance ?? 0)
      : transactions.last.balanceAfter;

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
      transactions = await _repository.fetchStatement(
        companyId: companyId,
        customerId: customerId,
        fromDate: fromDate,
        toDate: toDate,
      );
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
        name: '${current.name}-statement.pdf',
        onLayout: (_) => _buildPdf(current),
      );
    } catch (_) {
      _showError('customers_statement_pdf_error');
    } finally {
      isPrinting = false;
      if (!isClosed) update();
    }
  }

  Future<Uint8List> _buildPdf(CustomerModel current) async {
    final doc = pw.Document();
    pw.MemoryImage? logo;
    try {
      final bytes = await rootBundle.load(ImageAssest.logo);
      logo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      logo = null;
    }
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final date = DateFormat.yMd();

    doc.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(28)),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null) pw.Image(logo, width: 64, height: 64),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Jayatwa Trading Establishment',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text('Jordan'),
                    pw.Text('jtrdest@gmail.com'),
                    pw.Text('www.fujikaindustries.com'),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Customer Statement',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Customer: ${current.name}'),
          if (current.phone.isNotEmpty) pw.Text('Phone: ${current.phone}'),
          if (current.addressText.isNotEmpty)
            pw.Text('Address: ${current.addressText}'),
          pw.Text('Current balance: ${money.format(current.currentBalance)}'),
          pw.Text(
            'Date range: ${fromDate == null ? 'All' : date.format(fromDate!)} - ${toDate == null ? 'All' : date.format(toDate!)}',
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Date',
              'Type',
              'Number',
              'Debit',
              'Credit',
              'Balance',
            ],
            data: transactions
                .map(
                  (transaction) => [
                    date.format(transaction.transactionDate),
                    transaction.transactionType,
                    transaction.sourceNumber,
                    money.format(transaction.debitAmount),
                    money.format(transaction.creditAmount),
                    money.format(transaction.balanceAfter),
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Total debit: ${money.format(totalDebit)}'),
                  pw.Text('Total credit: ${money.format(totalCredit)}'),
                  pw.Text(
                    'Final balance: ${money.format(finalBalance)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
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
