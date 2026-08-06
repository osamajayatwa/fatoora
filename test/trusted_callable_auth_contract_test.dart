import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'trusted callables share the default app, region, and refreshed auth',
    () {
      final client = File(
        'lib/core/firebase/trusted_callable_client.dart',
      ).readAsStringSync();
      final invoiceRepository = File(
        'lib/features/invoices/data/repositories/invoice_repository.dart',
      ).readAsStringSync();
      final returnRepository = File(
        'lib/features/sales_returns/data/repositories/'
        'sales_return_repository.dart',
      ).readAsStringSync();
      final receiptRepository = File(
        'lib/features/receipts/data/repositories/receipt_repository.dart',
      ).readAsStringSync();
      final expenseRepository = File(
        'lib/features/expenses/data/repositories/expense_repository.dart',
      ).readAsStringSync();
      final itemRepository = File(
        'lib/features/items/data/repositories/item_repository.dart',
      ).readAsStringSync();

      expect(client, contains("static const String region = 'us-central1'"));
      expect(client, contains('final app = Firebase.app()'));
      expect(client, contains('FirebaseAuth.instanceFor(app: app)'));
      expect(
        client,
        contains('FirebaseFunctions.instanceFor(app: app, region: region)'),
      );
      expect(client, contains('_auth.app.name != _app.name'));
      expect(client, contains('_functions.app.name != _app.name'));
      expect(client, contains('.authStateChanges()'));
      expect(client, contains('.getIdToken(true)'));
      expect(client, contains(r'uid=$uid'));
      expect(client, contains(r'app=${_app.name}'));
      expect(client, contains(r'project=${_app.options.projectId}'));
      expect(client, contains(r'region=$region'));
      expect(client, contains('tokenRefresh='));
      expect(client, isNot(contains('useFunctionsEmulator')));

      for (final repository in [
        invoiceRepository,
        returnRepository,
        receiptRepository,
        expenseRepository,
        itemRepository,
      ]) {
        expect(repository, contains('TrustedCallableClient.forDefaultApp'));
        expect(repository, contains('.callAuthenticated<'));
        expect(repository, isNot(contains('.httpsCallable(')));
      }
    },
  );
}
