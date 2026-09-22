import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cash total aggregates have unfiltered admin and rep indexes', () {
    final manifest =
        jsonDecode(File('firestore.indexes.json').readAsStringSync())
            as Map<String, dynamic>;
    final indexes = (manifest['indexes'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((index) => index['collectionGroup'] == 'cash_movements')
        .map(_fieldNames)
        .toSet();

    expect(indexes, contains('direction,amount'));
    expect(indexes, contains('salesRepId,cashAccount,direction,amount'));
  });
}

String _fieldNames(Map<String, dynamic> index) {
  return (index['fields'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map((field) => field['fieldPath'] as String)
      .join(',');
}
