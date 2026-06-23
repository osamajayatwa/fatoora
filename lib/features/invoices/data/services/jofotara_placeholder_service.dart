import 'package:cloud_functions/cloud_functions.dart';

class JofotaraPlaceholderService {
  JofotaraPlaceholderService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<void> submitInvoice({
    required String companyId,
    required String invoiceId,
  }) async {
    final callable = _functions.httpsCallable('submitInvoiceToJoFotara');
    await callable.call(<String, dynamic>{
      'companyId': companyId,
      'invoiceId': invoiceId,
    });
  }
}
