import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';

class SalesReturnContext {
  const SalesReturnContext._();

  static Map<String, dynamic> arguments(Object? value) {
    if (value is! Map) return const {};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static String readString(Map<String, dynamic> arguments, String key) {
    final value = arguments[key];
    return value is String ? value.trim() : '';
  }

  static String resolveCompanyId(
    MyServices services,
    Map<String, dynamic> arguments,
  ) {
    final fromArguments = readString(arguments, 'companyId');
    if (fromArguments.isNotEmpty) return fromArguments;
    return services.sharedPreferences.getString('companyId') ??
        AuthRepository.defaultCompanyId;
  }
}
