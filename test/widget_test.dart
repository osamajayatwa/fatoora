import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'uid': 'test-user',
      'name': 'Test User',
      'email': 'test@example.com',
      'role': 'pending_sales_rep',
      'approvalStatus': 'pending',
      'companyId': 'default_company',
      'active': false,
      'step': '1',
    });
    Get.reset();
    await Get.putAsync(() => MyServices().init());
  });

  tearDown(Get.reset);

  testWidgets('pending user starts on waiting approval screen', (tester) async {
    Get.put(LocaleController());

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('Waiting for admin approval'), findsOneWidget);
    expect(
      find.text('Signed in successfully. Waiting for admin approval.'),
      findsOneWidget,
    );
  });
}
