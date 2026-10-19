import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/customers/controllers/customer_details_controller.dart';
import 'package:fatoora/features/customers/controllers/customer_error_mapper.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:fatoora/features/customers/view/screens/customer_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);
  test(
    'assignment overrides creator; legacy fallback and serialization preserve original history',
    () {
      final legacy = CustomerModel.fromMap({
        'id': 'customer',
        'createdByUid': 'rep-a',
        'createdByName': 'Original creator',
      });
      expect(legacy.isAssignedTo('rep-a'), isTrue);
      expect(legacy.hasExplicitAssignment, isFalse);
      final unversioned = CustomerModel.fromMap({
        ...legacy.toMap(),
        'assignedToUid': 'rep-b',
      });
      expect(unversioned.isAssignedTo('rep-a'), isTrue);
      expect(unversioned.isAssignedTo('rep-b'), isFalse);
      expect(legacy.toMap().containsKey('assignedToUid'), isFalse);
      final assigned = legacy.copyWith(
        assignedToUid: 'rep-b',
        assignedToName: 'Rep B',
        assignedToRole: 'sales_rep',
        assignmentRevision: 3,
      );
      final parsed = CustomerModel.fromMap(assigned.toMap());
      expect(parsed.isAssignedTo('rep-a'), isFalse);
      expect(parsed.isAssignedTo('rep-b'), isTrue);
      expect(parsed.createdByUid, 'rep-a');
      expect(parsed.createdByName, 'Original creator');
      expect(parsed.assignmentRevision, 3);
      expect(
        CustomerModel.fromMap({
          ...legacy.toMap(),
          'assignedToUid': '',
          'assignmentVersion': 1,
        }).isAssignedTo('rep-a'),
        isFalse,
      );
    },
  );
  test('stale assignment conflict has a dedicated translated error', () {
    final error = CustomerRepositoryException(
      CustomerRepositoryError.unknown,
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Assignment changed',
        details: {'reason': 'customer-assignment-stale'},
      ),
    );
    expect(CustomerErrorMapper.messageKey(error), 'customers_assignment_stale');
  });
  for (final language in ['en', 'ar']) {
    testWidgets(
      'Admin $language confirms current/new assignees and reason without changing creator/balances',
      (tester) async {
        final repo = _Repository();
        final controller = await _pump(tester, repo, language: language);
        expect(controller.customer!.createdByUid, 'admin');
        await tester.tap(
          find.byKey(const ValueKey('customer-reassign-action')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('customer-assignment-confirm')),
        );
        await tester.pumpAndSettle();
        expect(repo.calls, isEmpty);
        expect(find.text('customers_assignee_required'.tr), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('customer-new-assignee')));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Rep B').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('customer-assignment-reason')),
          ' Territory transfer ',
        );
        await tester.tap(
          find.byKey(const ValueKey('customer-assignment-confirm')),
        );
        await tester.pumpAndSettle();
        expect(repo.calls, ['rep-b:Territory transfer']);
        expect(controller.customer!.effectiveAssigneeUid, 'rep-b');
        expect(controller.customer!.createdByUid, 'admin');
        expect(controller.customer!.currentBalance, 123);
        expect(controller.customer!.totalSales, 150);
        expect(controller.customer!.totalPaid, 27);
        expect(controller.isReassigning, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'Sales Rep has no reassignment action and controller cannot invoke it',
    (tester) async {
      final repo = _Repository();
      final controller = await _pump(tester, repo, role: 'sales_rep');
      expect(
        find.byKey(const ValueKey('customer-reassign-action')),
        findsNothing,
      );
      await controller.reassignCustomer();
      expect(repo.calls, isEmpty);
      expect(repo.candidateLoads, 0);
    },
  );
  testWidgets('dismissed reassignment confirmation performs no mutation', (
    tester,
  ) async {
    final repo = _Repository();
    final controller = await _pump(tester, repo);
    await tester.tap(find.byKey(const ValueKey('customer-reassign-action')));
    await tester.pumpAndSettle();
    Get.back();
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    expect(controller.customer!.effectiveAssigneeUid, 'admin');
    expect(controller.isReassigning, isFalse);
  });
}

Future<CustomerDetailsController> _pump(
  WidgetTester tester,
  _Repository repo, {
  String role = 'admin',
  String language = 'en',
}) async {
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'uid': role,
    'role': role,
  });
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  final controller = Get.put(
    CustomerDetailsController(repository: repo, myServices: services),
  );
  await tester.pumpWidget(
    GetMaterialApp(
      translations: MyTranslation(),
      locale: Locale(language),
      initialRoute: AppRoute.customerDetailsPath('customer'),
      getPages: [
        GetPage(
          name: AppRoute.customerDetails,
          page: () => const CustomerDetailsScreen(),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

class _Repository implements CustomerRepository {
  final calls = <String>[];
  int candidateLoads = 0;
  CustomerModel current = CustomerModel.fromMap({
    'id': 'customer',
    'companyId': 'default_company',
    'name': 'Customer',
    'createdByUid': 'admin',
    'createdByName': 'Original Admin',
    'createdByRole': 'admin',
    'assignedToUid': 'admin',
    'assignedToName': 'Current Admin',
    'assignedToRole': 'admin',
    'assignmentRevision': 0,
    'currentBalance': 123,
    'totalSales': 150,
    'totalPaid': 27,
  });
  @override
  Future<CustomerModel> getCustomer({
    String companyId = 'default_company',
    required String customerId,
  }) async => current;
  @override
  Future<CustomerTransactionModel?> getOpeningBalance({
    String companyId = 'default_company',
    required String customerId,
  }) async => null;
  @override
  Future<List<AppUserModel>> fetchAssignmentCandidates({
    required String companyId,
  }) async {
    candidateLoads++;
    return [
      AppUserModel.fromMap({
        'uid': 'rep-b',
        'name': 'Rep B',
        'role': 'sales_rep',
        'companyId': companyId,
        'active': true,
        'approvalStatus': 'approved',
      }),
    ];
  }

  @override
  Future<CustomerModel> reassignCustomer({
    required CustomerModel customer,
    required String assignedToUid,
    required String reason,
  }) async {
    calls.add('$assignedToUid:$reason');
    expect(customer.assignmentRevision, 0);
    current = customer.copyWith(
      assignedToUid: assignedToUid,
      assignedToName: 'Rep B',
      assignedToRole: 'sales_rep',
      assignmentRevision: 1,
    );
    return current;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
