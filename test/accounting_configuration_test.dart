import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/localization/accounting_configuration_translations.dart';
import 'package:fatoora/features/settings/data/models/accounting_configuration_model.dart';
import 'package:fatoora/features/settings/view/screens/accounting_configuration_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(
          File(
            'test/fixtures/accounting_configuration.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> response({
  int revision = 1,
  Map<String, dynamic>? config,
}) => {
  'schemaVersion': 1,
  'companyId': 'synthetic-company',
  'bookId': 'draft-book',
  'revision': revision,
  'configuration': revision == 0 ? null : config ?? fixture(),
  'readiness': revision == 0
      ? null
      : {
          'configurationComplete': true,
          'postingEnabled': false,
          'approvalStatus': 'unreviewed',
          'missing': <String>[],
        },
};
AccountingConfigurationSnapshot snapshot({
  int revision = 1,
  Map<String, dynamic>? config,
}) => AccountingConfigurationSnapshot.fromMap(
  response(revision: revision, config: config),
  companyId: 'synthetic-company',
  bookId: 'draft-book',
);

void main() {
  tearDown(Get.reset);
  test('DTO preserves exact tax strings and immutable draft data', () {
    final s = snapshot();
    expect(
      (s.configuration!['taxCodes'] as List).first['ratePercent'],
      '16.000000',
    );
    expect(() => s.configuration!['currency'] = 'USD', throwsUnsupportedError);
    expect(
      () => (s.configuration!['accounts'] as List).clear(),
      throwsUnsupportedError,
    );
  });
  for (final kind in ['scope', 'posting', 'approval', 'malformed']) {
    test('DTO rejects $kind response', () {
      final r = response();
      if (kind == 'scope') {
        r['bookId'] = 'other';
      }
      if (kind == 'posting') {
        (r['readiness'] as Map)['postingEnabled'] = true;
      }
      if (kind == 'approval') {
        (r['readiness'] as Map)['approvalStatus'] = 'approved';
      }
      if (kind == 'malformed') {
        (r['configuration'] as Map)['periods'] = 'bad';
      }
      expect(
        () => AccountingConfigurationSnapshot.fromMap(
          r,
          companyId: 'synthetic-company',
          bookId: 'draft-book',
        ),
        throwsFormatException,
      );
    });
  }
  test('English and Arabic cover the same configuration labels', () {
    expect(
      accountingConfigurationArabicTranslations.keys.toSet(),
      accountingConfigurationEnglishTranslations.keys.toSet(),
    );
  });
  for (final locale in ['en', 'ar']) {
    testWidgets('loaded configuration renders at 320px and 2x in $locale', (
      tester,
    ) async {
      await pumpEditor(tester, locale: locale, textScale: 2);
      expect(find.byKey(const ValueKey('accounting-name')), findsOneWidget);
      expect(find.text('Synthetic test book'), findsOneWidget);
      expect(find.textContaining('accounting_'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('accounting-save')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'save sends full draft and optimistic revision through the existing callback',
    (tester) async {
      Map<String, dynamic>? sent;
      int? revision;
      await pumpEditor(
        tester,
        save: (book, r, c) async {
          expect(book, 'draft-book');
          sent = jsonDecode(jsonEncode(c)) as Map<String, dynamic>;
          revision = r;
          return snapshot(revision: 2, config: c);
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('accounting-name')),
        'Reviewed draft name',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('accounting-save')));
      await tester.tap(find.byKey(const ValueKey('accounting-save')));
      await tester.pumpAndSettle();
      expect(sent!['name'], 'Reviewed draft name');
      expect(revision, 1);
      expect(sent!.containsKey('journalPostingEnabled'), false);
      expect(find.text('Saved revision: 2'), findsOneWidget);
    },
  );
  testWidgets(
    'lost acknowledgement locks editing and retries the same payload and revision',
    (tester) async {
      final attempts = <String>[];
      int count = 0;
      await pumpEditor(
        tester,
        save: (book, r, c) async {
          attempts.add(jsonEncode([book, r, c]));
          if (count++ == 0) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'lost response',
            );
          }
          return snapshot(revision: 2, config: c);
        },
      );
      final save = find.byKey(const ValueKey('accounting-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Retry the same save'), findsOneWidget);
      expect(
        tester
            .widget<AbsorbPointer>(
              find.byKey(const ValueKey('accounting-editable-fields')),
            )
            .absorbing,
        true,
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(attempts.length, 2);
      expect(attempts[0], attempts[1]);
      expect(find.text('Saved revision: 2'), findsOneWidget);
    },
  );
  testWidgets(
    'revision conflict preserves edits and allows reload instead of overwriting',
    (tester) async {
      await pumpEditor(
        tester,
        save: (book, r, c) async =>
            throw FirebaseFunctionsException(code: 'aborted', message: 'stale'),
      );
      await tester.enterText(
        find.byKey(const ValueKey('accounting-name')),
        'Unsaved draft',
      );
      final save = find.byKey(const ValueKey('accounting-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.textContaining('Reload the draft'), findsOneWidget);
      expect(find.text('Unsaved draft'), findsOneWidget);
      expect(
        tester
            .widget<AbsorbPointer>(
              find.byKey(const ValueKey('accounting-editable-fields')),
            )
            .absorbing,
        false,
      );
    },
  );
  testWidgets('account dialog remains usable on a narrow screen', (
    tester,
  ) async {
    await pumpEditor(tester);
    final add = find.text('Add account');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'new book starts with explicit blank policy fields and no assumed currency',
    (tester) async {
      await pumpEditor(tester, empty: true);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('accounting-currency')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('accounting-moneyScale')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('Unknown'), findsWidgets);
    },
  );
}

Future<void> pumpEditor(
  WidgetTester tester, {
  String locale = 'en',
  double textScale = 1,
  bool empty = false,
  SaveAccountingConfiguration? save,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    GetMaterialApp(
      locale: Locale(locale),
      translations: MyTranslation(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AccountingConfigurationEditor(
            load: (id) async => snapshot(revision: empty ? 0 : 1),
            save:
                save ??
                (id, r, c) async => snapshot(revision: r + 1, config: c),
          ),
        ),
      ),
    ),
  );
  await tester.enterText(
    find.byKey(const ValueKey('accounting-bookId')),
    'draft-book',
  );
  await tester.tap(find.byKey(const ValueKey('accounting-load')));
  await tester.pumpAndSettle();
}
