import 'dart:async';

import 'package:fatoora/features/customers/data/models/customer_opening_balance.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/customers/view/widgets/customer_opening_balance_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  for (final size in <Size>[const Size(320, 640), const Size(640, 320)]) {
    testWidgets(
      'opening balance dialog is responsive at ${size.width}x${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          GetMaterialApp(
            home: Scaffold(
              body: CustomerOpeningBalanceDialog(
                customerName: 'Legacy Customer',
                onSubmit:
                    ({
                      required balanceType,
                      required amount,
                      required transactionDate,
                      required notes,
                    }) async => _openingTransaction(),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(CustomerOpeningBalanceDialog), findsOneWidget);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'successful save closes the opening balance dialog exactly once',
    (tester) async {
      var submissions = 0;
      CustomerTransactionModel? result;
      await tester.pumpWidget(
        GetMaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showDialog<CustomerTransactionModel>(
                    context: context,
                    builder: (_) => CustomerOpeningBalanceDialog(
                      customerName: 'Legacy Customer',
                      onSubmit:
                          ({
                            required balanceType,
                            required amount,
                            required transactionDate,
                            required notes,
                          }) async {
                            submissions++;
                            return _openingTransaction();
                          },
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '1500');
      await tester.tap(find.text('customers_post_opening_balance'));
      await tester.pumpAndSettle();

      expect(submissions, 1);
      expect(result?.amount, 1500);
      expect(find.byType(CustomerOpeningBalanceDialog), findsNothing);
    },
  );

  testWidgets('failed save keeps form open and always resets its spinner', (
    tester,
  ) async {
    var submissions = 0;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: CustomerOpeningBalanceDialog(
            customerName: 'Legacy Customer',
            onSubmit:
                ({
                  required balanceType,
                  required amount,
                  required transactionDate,
                  required notes,
                }) async {
                  submissions++;
                  return null;
                },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, '25');
    await tester.tap(find.text('customers_post_opening_balance'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerOpeningBalanceDialog), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(submissions, 1);
    await tester.tap(find.text('customers_post_opening_balance'));
    await tester.pumpAndSettle();
    expect(submissions, 2);
  });

  testWidgets('save button blocks duplicate taps while posting', (
    tester,
  ) async {
    var submissions = 0;
    final pending = Completer<CustomerTransactionModel?>();
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: CustomerOpeningBalanceDialog(
            customerName: 'Legacy Customer',
            onSubmit:
                ({
                  required balanceType,
                  required amount,
                  required transactionDate,
                  required notes,
                }) {
                  submissions++;
                  return pending.future;
                },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, '25');
    await tester.tap(find.text('customers_post_opening_balance'));
    await tester.pump();
    await tester.tap(find.text('customers_post_opening_balance'));
    await tester.pump();

    expect(submissions, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('existing opening balance is read-only and shows its details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: CustomerOpeningBalanceDetailsDialog(
            transaction: _openingTransaction(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('customers_opening_balance_already_registered'),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('OPENING'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit dialog previews values and requires an adjustment reason', (
    tester,
  ) async {
    var submissions = 0;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: CustomerOpeningBalanceEditDialog(
            customerName: 'Legacy Customer',
            transaction: _openingTransaction(),
            onSubmit:
                ({
                  required balanceType,
                  required amount,
                  required reason,
                }) async {
                  submissions++;
                  return _openingTransaction();
                },
          ),
        ),
      ),
    );

    expect(find.text('customers_opening_balance_old_value'), findsOneWidget);
    expect(find.text('customers_opening_balance_new_value'), findsOneWidget);
    expect(find.text('customers_opening_balance_difference'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '1200');
    final saveButton = find.text('customers_save_opening_balance_change');
    await tester.ensureVisible(saveButton);
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pump();

    expect(submissions, 0);
    expect(
      find.text('customers_opening_balance_reason_required'),
      findsOneWidget,
    );
  });

  testWidgets('edit dialog blocks duplicate submissions and resets loading', (
    tester,
  ) async {
    var submissions = 0;
    CustomerOpeningBalanceType? submittedType;
    String? submittedReason;
    final pending = Completer<CustomerTransactionModel?>();
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: CustomerOpeningBalanceEditDialog(
            customerName: 'Legacy Customer',
            transaction: _openingTransaction(),
            onSubmit:
                ({required balanceType, required amount, required reason}) {
                  submissions++;
                  submittedType = balanceType;
                  submittedReason = reason;
                  return pending.future;
                },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, '1200');
    await tester.enterText(find.byType(TextFormField).last, 'Verified records');
    final saveButton = find.text('customers_save_opening_balance_change');
    await tester.ensureVisible(saveButton);
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pump();

    expect(submissions, 1);
    expect(submittedType, CustomerOpeningBalanceType.customerOwes);
    expect(submittedReason, 'Verified records');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(CustomerOpeningBalanceEditDialog), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('successful opening balance edit closes exactly once', (
    tester,
  ) async {
    var submissions = 0;
    CustomerTransactionModel? result;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showDialog<CustomerTransactionModel>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => CustomerOpeningBalanceEditDialog(
                    customerName: 'Legacy Customer',
                    transaction: _openingTransaction(),
                    onSubmit:
                        ({
                          required balanceType,
                          required amount,
                          required reason,
                        }) async {
                          submissions++;
                          return _openingTransaction();
                        },
                  ),
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '1200');
    await tester.enterText(find.byType(TextFormField).last, 'Verified records');
    final saveButton = find.text('customers_save_opening_balance_change');
    await tester.ensureVisible(saveButton);
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(submissions, 1);
    expect(result, isNotNull);
    expect(find.byType(CustomerOpeningBalanceEditDialog), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

CustomerTransactionModel _openingTransaction() {
  final date = DateTime(2025, 12, 31);
  return CustomerTransactionModel(
    id: 'customer-1_opening_balance',
    companyId: 'default_company',
    customerId: 'customer-1',
    customerName: 'Legacy Customer',
    transactionType: 'opening_balance',
    type: 'opening_balance',
    sourceCollection: 'customer_transactions',
    sourceId: 'customer-1_opening_balance',
    sourceNumber: 'OPENING',
    transactionDate: date,
    debitAmount: 1500,
    creditAmount: 0,
    balanceBefore: 0,
    balanceAfter: 1500,
    openingBalanceType: 'customer_owes',
    amount: 1500,
    signedAmount: 1500,
    notes: 'Legacy debt',
    createdByUid: 'admin',
    createdByName: 'Admin',
    createdByRole: 'admin',
    salesRepId: '',
    salesRepName: '',
    createdAt: date,
  );
}
