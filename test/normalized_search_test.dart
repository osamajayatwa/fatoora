import 'dart:convert';
import 'dart:io';
import 'package:fatoora/core/search/normalized_search.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases =
      jsonDecode(
            File('test/fixtures/phase2_search_cases.json').readAsStringSync(),
          )
          as List;
  for (final record in cases) {
    test('normalized phrase prefixes: ${record['value']}', () {
      final value = record['value'] as String;
      expect(normalizeSearchText(value), record['normalized']);
      final keywords = buildNormalizedSearchKeywords([value]);
      for (final query in record['matches'] as List) {
        expect(keywords, contains(normalizeSearchText(query as String)));
      }
      for (final query in record['misses'] as List) {
        expect(keywords, isNot(contains(normalizeSearchText(query as String))));
      }
      expect(keywords, orderedEquals(keywords.toSet().toList()..sort()));
    });
  }

  test(
    'invoice/customer names, numbers and item/model keywords share normalization',
    () {
      final invoice = InvoiceModel.buildSearchKeywords(
        invoiceNumber: 'INV-2026-0123',
        customerName: 'أحمد  عبد الرحمن',
        customerPhone: '',
        salesRepName: 'Sales  Rep',
        itemNames: const ['Water  Pump'],
        dateString: '2026-10-19',
      );
      expect(
        invoice,
        containsAll(['احمد عبد', 'inv 2026 01', 'water pu', 'sales rep']),
      );
      final item = ItemModel.buildSearchKeywords([
        '  Water   Pump  ',
        'MD-123',
      ]);
      expect(item, containsAll(['water pu', 'md 12', 'md-12']));
      expect(ItemModel.normalizeSearch(' أَحمد   عبد '), 'احمد عبد');
    },
  );

  test(
    'keyword budget is bounded, deterministic and preserves primary fields',
    () {
      final values = [
        'INV-2026-00123',
        'Primary Customer',
        for (var i = 0; i < 100; i++)
          'Long catalog item number $i with many words',
      ];
      final keywords = buildNormalizedSearchKeywords(values);
      expect(keywords.length, lessThanOrEqualTo(searchKeywordLimit));
      expect(
        keywords,
        containsAll(['inv-2026-00123', 'primary customer', 'primary cust']),
      );
      expect(buildNormalizedSearchKeywords(values), keywords);
    },
  );

  test(
    'debounce/minimum policy collapses internal whitespace without loading pages',
    () {
      expect(serverSearchTerm('  Acme \t Trading \n Co  '), 'Acme Trading Co');
      expect(serverSearchTerm(' ع '), '');
      expect(serverSearchTerm('ab'), 'ab');
      expect(serverSearchDebounce.inMilliseconds, 450);
    },
  );
}
