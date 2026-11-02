import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';

typedef CustomerQueryCall =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);

/// Mixed legacy/versioned ownership is authorized and paginated on the server.
/// No creator candidates or incomplete filtered pages are exposed to the client.
class AccessibleCustomerQuery {
  AccessibleCustomerQuery(TrustedCallableClient client)
    : _call = ((payload) async {
        final result = await client.callAuthenticated<Map<String, dynamic>>(
          'listAccessibleCustomers',
          payload,
        );
        return result.data;
      });

  AccessibleCustomerQuery.withCall(this._call);

  final CustomerQueryCall _call;

  Future<AccessibleCustomerPage> fetchPage({
    required String companyId,
    String searchText = '',
    bool activeOnly = true,
    String order = 'name',
    bool includeTotals = false,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    if (after != null && after is! ServerPageCursor) {
      throw ArgumentError('Expected a customer server cursor');
    }
    final result = await _call({
      'companyId': companyId,
      'searchText': CustomerModel.normalizeText(searchText),
      'activeOnly': activeOnly,
      'order': order,
      'includeTotals': includeTotals,
      'pageSize': pageSize.clamp(1, 200).toInt(),
      if (after != null) 'after': (after as ServerPageCursor).serverData,
    }).timeout(const Duration(seconds: 30));
    final items = (result['customers'] as List)
        .map(
          (raw) => CustomerModel.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList(growable: false);
    final rawCursor = result['cursor'];
    final hasMore = result['hasMore'] == true;
    if (hasMore && (items.isEmpty || rawCursor is! Map)) {
      throw FirebaseFunctionsException(
        code: 'data-loss',
        message: 'Invalid customer page',
      );
    }
    return AccessibleCustomerPage(
      items: items,
      cursor: rawCursor is Map
          ? FirestorePageCursor.server(Map<String, dynamic>.from(rawCursor))
          : null,
      hasMore: hasMore,
      totalReceivables: (result['totalReceivables'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<List<CustomerModel>> fetchAll({
    required String companyId,
    String searchText = '',
    bool activeOnly = true,
    String order = 'name',
    int pageSize = 150,
  }) async {
    final customers = <CustomerModel>[];
    FirestorePageCursor? after;
    do {
      final page = await fetchPage(
        companyId: companyId,
        searchText: searchText,
        activeOnly: activeOnly,
        order: order,
        after: after,
        pageSize: pageSize,
      );
      customers.addAll(page.items);
      if (!page.hasMore) break;
      after = page.cursor;
    } while (true);
    return customers;
  }
}

class AccessibleCustomerPage extends FirestorePage<CustomerModel> {
  const AccessibleCustomerPage({
    required super.items,
    required super.cursor,
    required super.hasMore,
    required this.totalReceivables,
  });

  final double totalReceivables;
}
