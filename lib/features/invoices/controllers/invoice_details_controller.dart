import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/app_feature_flags.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/constants/imageassests.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/invoices/controllers/invoice_context.dart';
import 'package:fatoora/features/invoices/controllers/invoice_error_mapper.dart';
import 'package:fatoora/features/invoices/controllers/invoice_page_navigation.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class InvoiceDetailsController extends GetxController
    with InvoicePageNavigation {
  InvoiceDetailsController({
    required InvoiceRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final InvoiceRepository _repository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'invoice_load_error';
  String companyId = '';
  String invoiceId = '';
  InvoiceModel? invoice;
  bool isSubmitting = false;
  bool isPrinting = false;

  bool get canEdit => invoice?.canEdit ?? false;
  bool get canSubmit =>
      AppFeatureFlags.jofotaraEnabled &&
      invoice?.invoiceType == InvoiceType.electronic &&
      (invoice?.invoiceStatus == InvoiceStatus.draft ||
          invoice?.invoiceStatus == InvoiceStatus.rejected);

  @override
  void onReady() {
    super.onReady();
    loadInvoice();
  }

  Future<void> loadInvoice() async {
    final args = InvoiceContext.arguments(Get.arguments);
    companyId = InvoiceContext.resolveCompanyId(_myServices, args);
    invoiceId = InvoiceContext.readString(args, 'invoiceId');
    if (companyId.isEmpty || invoiceId.isEmpty) {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'invoice_not_found';
      update();
      return;
    }

    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'invoice_load_error';
    update();
    try {
      invoice = await _repository.getInvoiceById(
        companyId: companyId,
        invoiceId: invoiceId,
      );
      if (invoice == null) {
        statusRequest = StatusRequest.failure;
        loadErrorMessageKey = 'invoice_not_found';
      } else {
        statusRequest = StatusRequest.success;
      }
    } catch (error) {
      statusRequest = InvoiceErrorMapper.status(error);
      loadErrorMessageKey = InvoiceErrorMapper.messageKey(
        error,
        fallback: 'invoice_load_error',
      );
      _showError(loadErrorMessageKey);
    }
    if (!isClosed) update();
  }

  Future<void> editInvoice() async {
    final current = invoice;
    if (current == null) return;
    if (!current.canEdit) {
      _showError('confirmed_invoice_locked');
      return;
    }
    final changed = await Get.toNamed(
      AppRoute.invoiceForm,
      arguments: {
        'mode': 'edit',
        'companyId': current.companyId,
        'invoiceId': current.id,
      },
    );
    if (changed == true) await loadInvoice();
  }

  Future<void> submitElectronicInvoicePlaceholder() async {
    final current = invoice;
    if (current == null || !canSubmit || isSubmitting) return;
    isSubmitting = true;
    update();
    try {
      await _repository.submitElectronicInvoicePlaceholder(
        companyId: current.companyId,
        invoiceId: current.id,
      );
      _showSuccess('submission_success');
      await loadInvoice();
    } catch (error) {
      _showError(
        InvoiceErrorMapper.messageKey(error, fallback: 'submission_failed'),
      );
    } finally {
      isSubmitting = false;
      if (!isClosed) update();
    }
  }

  Future<void> printOrExportPlaceholder() async {
    final current = invoice;
    if (current == null || isPrinting) return;
    isPrinting = true;
    update();
    try {
      await Printing.layoutPdf(
        name: '${current.invoiceNumber}.pdf',
        onLayout: (_) => _buildInvoicePdf(current),
      );
    } catch (_) {
      _showError('invoice_pdf_error');
    } finally {
      isPrinting = false;
      if (!isClosed) update();
    }
  }

  Future<Uint8List> _buildInvoicePdf(InvoiceModel current) async {
    final document = pw.Document();
    pw.MemoryImage? logo;
    try {
      final bytes = await rootBundle.load(ImageAssest.logo);
      logo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      logo = null;
    }
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final date = DateFormat.yMd();
    final customer = current.customerSnapshot;

    document.addPage(
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
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Invoice',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(current.invoiceNumber),
                  pw.Text(date.format(current.invoiceDate)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Customer',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(customer?.name ?? ''),
                    if ((customer?.phone ?? '').isNotEmpty)
                      pw.Text(customer!.phone),
                    if ((customer?.address ?? '').isNotEmpty)
                      pw.Text(customer!.address),
                    if ((customer?.city ?? '').isNotEmpty)
                      pw.Text(customer!.city),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Due date: ${date.format(current.dueDate)}'),
                    pw.Text('Sales rep: ${current.salesRepName}'),
                    pw.Text('Payment: ${current.paymentType.value}'),
                    pw.Text('Status: ${current.paymentStatus.value}'),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Item',
              'Qty',
              'Unit',
              'Price',
              'Discount',
              'Tax',
              'Total',
            ],
            data: current.items
                .map(
                  (item) => [
                    item.itemName,
                    item.quantity.toStringAsFixed(3),
                    item.unit,
                    money.format(item.unitPrice),
                    money.format(item.discount),
                    money.format(item.taxAmount),
                    money.format(item.total),
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Subtotal: ${money.format(current.subtotal)}'),
                  pw.Text('Discount: ${money.format(current.totalDiscount)}'),
                  pw.Text('Tax: ${money.format(current.totalTax)}'),
                  pw.Text(
                    'Grand total: ${money.format(current.grandTotal)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text('Paid: ${money.format(current.paidAmount)}'),
                  pw.Text(
                    'Remaining: ${money.format(current.remainingAmount)}',
                  ),
                ],
              ),
            ],
          ),
          if (current.notes.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'Notes',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(current.notes),
          ],
        ],
      ),
    );
    return document.save();
  }

  Future<void> requestBack() {
    return leaveInvoicePage(fallbackRoute: AppRoute.invoices, result: true);
  }

  void _showSuccess(String messageKey) {
    Get.snackbar(
      'invoices'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.success,
      colorText: AppColor.surface,
    );
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'invoices'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }
}
