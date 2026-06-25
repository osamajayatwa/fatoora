import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';

class InvoiceContext {
  const InvoiceContext._();

  static Map<String, dynamic> arguments(Object? rawArguments) {
    if (rawArguments is! Map) return const {};
    return rawArguments.map((key, value) => MapEntry(key.toString(), value));
  }

  static String readString(Map<String, dynamic> arguments, String key) {
    final value = arguments[key];
    return value is String ? value.trim() : '';
  }

  static String resolveCompanyId(
    MyServices myServices,
    Map<String, dynamic> arguments,
  ) {
    final fromArgs = readString(arguments, 'companyId');
    if (fromArgs.isNotEmpty) return fromArgs;

    final preferences = myServices.sharedPreferences;
    for (final key in ['companyId', 'company_id']) {
      final value = preferences.getString(key);
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }

    return AuthRepository.defaultCompanyId;
  }
}
