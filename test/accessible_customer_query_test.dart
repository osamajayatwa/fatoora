import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/features/customers/data/repositories/accessible_customer_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mixed customer pages preserve server order and forward the opaque cursor',
    () async {
      final calls = <Map<String, dynamic>>[];
      final cursor = {
        'scope': 'server-bound-query',
        'id': 'legacy',
        'value': 'a',
      };
      final query = AccessibleCustomerQuery.withCall((payload) async {
        calls.add(payload);
        if (calls.length == 1) {
          return {
            'customers': [
              {
                'id': 'legacy',
                'createdByUid': 'rep-a',
                'createdAt': '2020-01-02T00:00:00.000Z',
              },
            ],
            'cursor': cursor,
            'hasMore': true,
          };
        }
        return {
          'customers': [
            {
              'id': 'incoming',
              'createdByUid': 'rep-b',
              'assignedToUid': 'rep-a',
              'assignmentVersion': 1,
            },
          ],
          'cursor': null,
          'hasMore': false,
        };
      });
      final customers = await query.fetchAll(
        companyId: 'company',
        searchText: '  عميل قديم  ',
        activeOnly: false,
        pageSize: 1,
      );
      expect(customers.map((c) => c.id), ['legacy', 'incoming']);
      expect(customers.every((c) => c.isAssignedTo('rep-a')), isTrue);
      expect(customers.first.createdAt.toUtc(), DateTime.utc(2020, 1, 2));
      expect(calls.first['searchText'], 'عميل قديم');
      expect(calls.first['activeOnly'], false);
      expect(calls.first.containsKey('after'), isFalse);
      expect(calls.last['after'], cursor);
      expect(calls.last['pageSize'], 1);
    },
  );

  test(
    'receivable page keeps server totals and balance cursor without local filtering',
    () async {
      Map<String, dynamic>? sent;
      final query = AccessibleCustomerQuery.withCall((payload) async {
        sent = payload;
        return {
          'customers': [
            {'id': 'legacy', 'createdByUid': 'rep-a', 'currentBalance': 80},
          ],
          'cursor': {'scope': 'balances', 'id': 'legacy', 'value': 80},
          'hasMore': true,
          'totalReceivables': 120,
        };
      });
      final page = await query.fetchPage(
        companyId: 'company',
        order: 'balance',
        includeTotals: true,
      );
      expect(page.totalReceivables, 120);
      expect(page.items.single.currentBalance, 80);
      expect(page.hasMore, isTrue);
      expect(page.cursor, isA<ServerPageCursor>());
      expect(sent!['order'], 'balance');
      expect(sent!['includeTotals'], isTrue);
    },
  );

  test(
    'empty pages terminate and unrelated callable errors propagate',
    () async {
      var count = 0;
      final query = AccessibleCustomerQuery.withCall((_) async {
        count++;
        return {'customers': [], 'cursor': null, 'hasMore': false};
      });
      expect(await query.fetchAll(companyId: 'company'), isEmpty);
      expect(count, 1);
      final failure = FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Transferred',
      );
      final denied = AccessibleCustomerQuery.withCall(
        (_) async => throw failure,
      );
      await expectLater(
        denied.fetchPage(companyId: 'company'),
        throwsA(same(failure)),
      );
    },
  );

  test(
    'malformed continuation cannot cause an infinite picker/export loop',
    () async {
      final query = AccessibleCustomerQuery.withCall(
        (_) async => {
          'customers': [],
          'cursor': {'id': 'bad'},
          'hasMore': true,
        },
      );
      await expectLater(
        query.fetchAll(companyId: 'company'),
        throwsA(isA<FirebaseFunctionsException>()),
      );
    },
  );
}
