import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';

class InvoiceNumberService {
  const InvoiceNumberService();

  Future<String> generate({
    required String companyId,
    required InvoiceType invoiceType,
  }) async {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final suffix = now.millisecondsSinceEpoch.toString().substring(7);
    final prefix = invoiceType == InvoiceType.electronic ? 'EINV' : 'INV';
    return '$prefix-$date-$suffix';
  }
}
