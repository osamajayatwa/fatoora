import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

class AppPdfLocalization {
  AppPdfLocalization._(this.languageCode);

  factory AppPdfLocalization.forLanguage(String languageCode) {
    return AppPdfLocalization._(
      languageCode.trim().toLowerCase() == 'ar' ? 'ar' : 'en',
    );
  }

  factory AppPdfLocalization.current() {
    final code = Get.locale?.languageCode.toLowerCase() ?? 'en';
    return AppPdfLocalization.forLanguage(code);
  }

  final String languageCode;

  bool get isArabic => languageCode == 'ar';
  String get localeName => isArabic ? 'ar' : 'en';
  pw.TextDirection get textDirection =>
      isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  pw.CrossAxisAlignment get startCrossAxis =>
      isArabic ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start;
  pw.Alignment get startAlignment =>
      isArabic ? pw.Alignment.centerRight : pw.Alignment.centerLeft;

  String t(String key) {
    final map = isArabic ? _ar : _en;
    return map[key] ?? _en[key] ?? key;
  }

  String date(DateTime value) =>
      _withoutDirectionalMarks(DateFormat.yMd(localeName).format(value));

  String money(num value) {
    final formatter = NumberFormat.currency(
      locale: localeName,
      symbol: isArabic ? 'د.أ ' : 'JOD ',
      decimalDigits: 3,
    );
    return _withoutDirectionalMarks(formatter.format(value));
  }

  String quantity(num value) {
    final rounded = (value * 1000).roundToDouble() / 1000;
    if (rounded == rounded.roundToDouble()) {
      return rounded.toStringAsFixed(0);
    }
    return rounded.toStringAsFixed(3);
  }

  String dateRange(DateTime? from, DateTime? to) {
    final all = t('all');
    return '${from == null ? all : date(from)} - ${to == null ? all : date(to)}';
  }

  String enumValue(String value) => t(value);

  String _withoutDirectionalMarks(String value) =>
      value.replaceAll(RegExp(r'[\u061C\u200E\u200F]'), '');

  static const Map<String, String> _en = {
    'all': 'All',
    'address': 'Address',
    'amount': 'Amount',
    'balance': 'Balance',
    'cash_in_hand': 'Cash in hand',
    'cash_report': 'Cash report',
    'company_country': 'Jordan',
    'credit': 'Credit',
    'customer': 'Customer',
    'customer_info': 'Customer info',
    'customer_statement': 'Customer statement',
    'date': 'Date',
    'date_range': 'Date range',
    'debit': 'Debit',
    'description': 'Description',
    'direction': 'Direction',
    'discount': 'Discount',
    'due_date': 'Due date',
    'final_balance': 'Final balance',
    'financial_posted': 'Financial posted',
    'grand_total': 'Grand total',
    'inventory_posted': 'Inventory posted',
    'invoice': 'Invoice',
    'invoice_date': 'Invoice date',
    'invoice_number': 'Invoice number',
    'sales_invoice': 'SALES INVOICE',
    'tax_invoice': 'TAX INVOICE',
    'invoice_status': 'Invoice status',
    'item': 'Item',
    'line_total': 'Line total',
    'notes': 'Notes',
    'no': 'No',
    'opening_balance': 'Opening balance',
    'original_invoice_number': 'Original invoice number',
    'paid_amount': 'Paid amount',
    'payment_method': 'Payment method',
    'payment_method_cash': 'Cash',
    'payment_method_bank': 'Bank transfer',
    'payment_method_cheque': 'Cheque',
    'payment_method_other': 'Other',
    'payment_status': 'Payment status',
    'payment_type': 'Payment type',
    'pdf_company_info': 'Company information',
    'pdf_footer': 'Footer',
    'pdf_generated_at': 'Generated at',
    'pdf_language_mode': 'PDF language mode',
    'pdf_prepared_by': 'Prepared by',
    'pdf_terms': 'Terms',
    'prepared_by': 'Prepared by',
    'quantity': 'Quantity',
    'quotation': 'Quotation',
    'quotation_date': 'Quotation date',
    'quotation_number': 'Quotation number',
    'quotation_status': 'Quotation status',
    'reason': 'Reason',
    'receipt': 'Receipt',
    'receipt_date': 'Receipt date',
    'receipt_number': 'Receipt number',
    'reference_number': 'Reference number',
    'refund_type': 'Refund type',
    'remaining_amount': 'Remaining amount',
    'return_date': 'Return date',
    'return_number': 'Return number',
    'running_balance': 'Running balance',
    'sales_rep': 'Sales rep',
    'sales_return': 'Sales return',
    'payment': 'Payment',
    'return': 'Return / credit note',
    'refund': 'Refund',
    'signature': 'Signature',
    'statement': 'Statement',
    'status': 'Status',
    'subtotal': 'Subtotal',
    'tax': 'Tax',
    'terms': 'Terms',
    'total': 'Total',
    'total_credit': 'Total credit',
    'total_debit': 'Total debit',
    'total_discount': 'Total discount',
    'total_in': 'Total in',
    'total_out': 'Total out',
    'total_tax': 'Total tax',
    'transaction_type': 'Transaction type',
    'type': 'Type',
    'unit': 'Unit',
    'unit_price': 'Unit price',
    'valid_until': 'Valid until',
    'yes': 'Yes',
    'phone': 'Phone',
    'city': 'City',
    'in': 'In',
    'out': 'Out',
    'cash': 'Cash',
    'partial': 'Partial',
    'paid': 'Paid',
    'unpaid': 'Unpaid',
    'partiallyPaid': 'Partially paid',
    'overdue': 'Overdue',
    'draft': 'Draft',
    'confirmed': 'Confirmed',
    'sent': 'Sent',
    'accepted': 'Accepted',
    'rejected': 'Rejected',
    'expired': 'Expired',
    'converted': 'Converted',
    'cancelled': 'Cancelled',
    'credit_customer_balance': 'Credit customer balance',
    'cash_refund': 'Cash refund',
    'invoice_cash': 'Cash invoice',
    'invoice_partial': 'Partial invoice payment',
    'receipt_cash': 'Cash receipt',
    'settlement_to_admin': 'Settlement to admin',
    'adjustment': 'Cash adjustment',
    'sales_return_cash_refund': 'Sales return cash refund',
  };

  static const Map<String, String> _ar = {
    'all': 'الكل',
    'address': 'العنوان',
    'amount': 'المبلغ',
    'balance': 'الرصيد',
    'cash_in_hand': 'النقد في الصندوق',
    'cash_report': 'تقرير النقد',
    'company_country': 'الأردن',
    'credit': 'دائن',
    'customer': 'العميل',
    'customer_info': 'معلومات العميل',
    'customer_statement': 'كشف حساب العميل',
    'date': 'التاريخ',
    'date_range': 'نطاق التاريخ',
    'debit': 'مدين',
    'description': 'الوصف',
    'direction': 'الاتجاه',
    'discount': 'الخصم',
    'due_date': 'تاريخ الاستحقاق',
    'final_balance': 'الرصيد النهائي',
    'financial_posted': 'تم الترحيل المالي',
    'grand_total': 'الإجمالي',
    'inventory_posted': 'تم ترحيل المخزون',
    'invoice': 'فاتورة',
    'invoice_date': 'تاريخ الفاتورة',
    'invoice_number': 'رقم الفاتورة',
    'sales_invoice': 'فاتورة بيع',
    'tax_invoice': 'فاتورة ضريبية',
    'invoice_status': 'حالة الفاتورة',
    'item': 'الصنف',
    'line_total': 'إجمالي السطر',
    'notes': 'ملاحظات',
    'no': 'لا',
    'opening_balance': 'الرصيد الافتتاحي',
    'original_invoice_number': 'رقم الفاتورة الأصلية',
    'paid_amount': 'المبلغ المدفوع',
    'payment_method': 'طريقة الدفع',
    'payment_method_cash': 'نقدي',
    'payment_method_bank': 'تحويل بنكي',
    'payment_method_cheque': 'شيك',
    'payment_method_other': 'أخرى',
    'payment_status': 'حالة الدفع',
    'payment_type': 'نوع الدفع',
    'pdf_company_info': 'بيانات الشركة',
    'pdf_footer': 'التذييل',
    'pdf_generated_at': 'تاريخ الإنشاء',
    'pdf_language_mode': 'لغة ملف PDF',
    'pdf_prepared_by': 'إعداد',
    'pdf_terms': 'الشروط',
    'prepared_by': 'أعده',
    'quantity': 'الكمية',
    'quotation': 'عرض سعر',
    'quotation_date': 'تاريخ عرض السعر',
    'quotation_number': 'رقم عرض السعر',
    'quotation_status': 'حالة عرض السعر',
    'reason': 'السبب',
    'receipt': 'إيصال',
    'receipt_date': 'تاريخ الإيصال',
    'receipt_number': 'رقم الإيصال',
    'reference_number': 'رقم المرجع',
    'refund_type': 'نوع الاسترداد',
    'remaining_amount': 'المبلغ المتبقي',
    'return_date': 'تاريخ المرتجع',
    'return_number': 'رقم المرتجع',
    'running_balance': 'الرصيد الجاري',
    'sales_rep': 'مندوب المبيعات',
    'sales_return': 'مرتجع مبيعات',
    'payment': 'دفعة',
    'return': 'مرتجع / إشعار دائن',
    'refund': 'استرداد',
    'signature': 'التوقيع',
    'statement': 'كشف حساب',
    'status': 'الحالة',
    'subtotal': 'المجموع الفرعي',
    'tax': 'الضريبة',
    'terms': 'الشروط',
    'total': 'الإجمالي',
    'total_credit': 'إجمالي الدائن',
    'total_debit': 'إجمالي المدين',
    'total_discount': 'إجمالي الخصم',
    'total_in': 'إجمالي الداخل',
    'total_out': 'إجمالي الخارج',
    'total_tax': 'إجمالي الضريبة',
    'transaction_type': 'نوع الحركة',
    'type': 'النوع',
    'unit': 'الوحدة',
    'unit_price': 'سعر الوحدة',
    'valid_until': 'صالح حتى',
    'yes': 'نعم',
    'phone': 'الهاتف',
    'city': 'المدينة',
    'in': 'داخل',
    'out': 'خارج',
    'cash': 'نقدي',
    'partial': 'جزئي',
    'paid': 'مدفوع',
    'unpaid': 'غير مدفوع',
    'partiallyPaid': 'مدفوع جزئيا',
    'overdue': 'متأخر',
    'draft': 'مسودة',
    'confirmed': 'مؤكدة',
    'sent': 'مرسل',
    'accepted': 'مقبول',
    'rejected': 'مرفوض',
    'expired': 'منتهي',
    'converted': 'محول',
    'cancelled': 'ملغاة',
    'credit_customer_balance': 'رصيد لصالح العميل',
    'cash_refund': 'استرداد نقدي',
    'invoice_cash': 'فاتورة نقدية',
    'invoice_partial': 'دفعة فاتورة جزئية',
    'receipt_cash': 'إيصال نقدي',
    'settlement_to_admin': 'تسوية للإدارة',
    'adjustment': 'تعديل نقدي',
    'sales_return_cash_refund': 'استرداد نقدي لمرتجع مبيعات',
  };
}
