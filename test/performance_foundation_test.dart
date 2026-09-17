import 'dart:io';

import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('item search keywords are normalized, unique, and deterministic', () {
    final first = ItemModel.buildSearchKeywords(const [
      '  MODEL-X  ',
      'Coffee Beans',
      'MODEL-X',
    ]);
    final second = ItemModel.buildSearchKeywords(const [
      '  MODEL-X  ',
      'Coffee Beans',
      'MODEL-X',
    ]);

    expect(first, second);
    expect(first, containsAll(<String>['model-x', 'model', 'coffee']));
    expect(first.toSet().length, first.length);
  });

  test('high-volume pickers use server pages and stale-request guards', () {
    final itemPicker = File(
      'lib/features/invoices/view/widgets/item_picker_sheet.dart',
    ).readAsStringSync();
    final customerPicker = File(
      'lib/features/customers/view/widgets/customer_picker_sheet.dart',
    ).readAsStringSync();

    expect(itemPicker, contains('fetchItemsPage'));
    expect(itemPicker, contains('_generation'));
    expect(customerPicker, contains('fetchCustomersPage'));
    expect(customerPicker, contains('_requestGeneration'));
    for (final source in <String>[itemPicker, customerPicker]) {
      expect(source, contains('serverSearchDebounce'));
      expect(source, isNot(contains('.getAllPages(')));
    }
  });

  test('performance caches expose explicit invalidation', () {
    final context = File(
      'lib/features/shared/business/business_user_context.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/core/settings/business_settings_resolver.dart',
    ).readAsStringSync();

    expect(context, contains('static void invalidateCache'));
    expect(context, contains('_inFlight'));
    expect(settings, contains('invalidateAppSettings'));
    expect(settings, contains('invalidateUserPreferences'));
    expect(settings, contains('_appSettingsInFlight'));
  });

  test('settings cache coalesces reads and invalidates explicitly', () async {
    var appReads = 0;
    var preferenceReads = 0;
    final resolver = BusinessSettingsResolver.withLoaders(
      appSettingsLoader: (_) async {
        appReads++;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return AppSettingsModel.defaults;
      },
      userPreferencesLoader: (_) async {
        preferenceReads++;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return UserPreferencesModel.defaults;
      },
    );

    await Future.wait([
      resolver.loadAppSettings('cache-company'),
      resolver.loadAppSettings('cache-company'),
    ]);
    await Future.wait([
      resolver.loadUserPreferences('cache-user'),
      resolver.loadUserPreferences('cache-user'),
    ]);
    expect(appReads, 1);
    expect(preferenceReads, 1);

    BusinessSettingsResolver.invalidateAppSettings('cache-company');
    BusinessSettingsResolver.invalidateUserPreferences('cache-user');
    await resolver.loadAppSettings('cache-company');
    await resolver.loadUserPreferences('cache-user');
    expect(appReads, 2);
    expect(preferenceReads, 2);
  });

  test('large accounting workbook uses an isolate off web', () {
    final source = File(
      'lib/features/financial_ledger/data/services/'
      'financial_ledger_excel_service.dart',
    ).readAsStringSync();

    expect(source, contains('compute('));
    expect(source, contains('kIsWeb'));
  });

  test(
    'customer statement pages detail rows but exports the full statement',
    () {
      final repository = File(
        'lib/features/customers/data/repositories/customer_repository.dart',
      ).readAsStringSync();
      final controller = File(
        'lib/features/customers/controllers/customer_statement_controller.dart',
      ).readAsStringSync();

      expect(repository, contains('fetchStatementPage'));
      expect(repository, contains('.getPage('));
      expect(repository, contains('fetchFullStatement'));
      expect(controller, contains('Future<void> loadMore()'));
      expect(controller, contains('fetchFullStatement('));
    },
  );

  test('cash screen pages details and reserves full reads for PDF export', () {
    final repository = File(
      'lib/features/financial/data/repositories/financial_repository.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/features/financial/controllers/cash_movements_controller.dart',
    ).readAsStringSync();

    expect(repository, contains('fetchCashPage'));
    expect(repository, contains('fetchCashMovementDetailsPage'));
    expect(repository, contains('_fetchCashMovementTotals'));
    expect(controller, contains('Future<void> loadMore()'));
    expect(controller, contains('fetchCashMovementDetailsPage('));
    expect(controller, contains('final exportSnapshot = await'));
  });

  test('current receivables page customer rows and aggregate the total', () {
    final repository = File(
      'lib/features/financial/data/repositories/financial_repository.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/features/financial/controllers/receivables_controller.dart',
    ).readAsStringSync();

    expect(repository, contains('fetchCurrentReceivablesPage'));
    expect(repository, contains("aggregate(sum('currentBalance'))"));
    expect(controller, contains('Future<void> loadMore()'));
    expect(controller, contains('fetchCurrentReceivablesPage('));
  });
}
