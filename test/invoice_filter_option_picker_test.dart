import 'dart:async';

import 'package:fatoora/features/invoices/data/models/invoice_list_query.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_filter_option_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'filter option search debounces, requires two chars, and submits',
    (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvoiceFilterOptionPicker(
              title: 'Customers',
              searchHint: 'Search',
              allLabel: 'All',
              selected: null,
              loadOptions: (searchText) async {
                calls.add(searchText);
                return const [];
              },
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(calls, ['']);

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, ['']);

      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump(const Duration(milliseconds: 449));
      expect(calls, ['']);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(calls, ['', 'ab']);

      await tester.enterText(find.byType(TextField), 'invoice');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(calls, ['', 'ab', 'invoice']);
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, ['', 'ab', 'invoice']);

      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump();
      expect(calls.last, '');
    },
  );

  testWidgets('stale filter option response cannot replace newer results', (
    tester,
  ) async {
    final pending = <String, Completer<List<InvoiceFilterOption>>>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvoiceFilterOptionPicker(
            title: 'Customers',
            searchHint: 'Search',
            allLabel: 'All',
            selected: null,
            loadOptions: (searchText) {
              if (searchText.isEmpty) return Future.value(const []);
              final completer = Completer<List<InvoiceFilterOption>>();
              pending[searchText] = completer;
              return completer.future;
            },
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'older');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'newer');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    pending['newer']!.complete(const [
      InvoiceFilterOption(id: 'new', label: 'New result'),
    ]);
    await tester.pump();
    expect(find.text('New result'), findsOneWidget);

    pending['older']!.complete(const [
      InvoiceFilterOption(id: 'old', label: 'Old result'),
    ]);
    await tester.pump();
    expect(find.text('New result'), findsOneWidget);
    expect(find.text('Old result'), findsNothing);
  });
}
