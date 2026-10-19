import 'dart:async';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/inventory/controllers/inventory_dashboard_controller.dart';
import 'package:fatoora/features/inventory/data/repositories/inventory_repository.dart';
import 'package:fatoora/features/invoices/controllers/invoices_list_controller.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_list_query.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);
  testWidgets(
    'invoice phrase pagination ignores old load-more and errors during a newer search',
    (tester) async {
      final repository = _Invoices();
      final controller = InvoicesListController(
        repository: repository,
        myServices: await _services(),
      );
      addTearDown(controller.onClose);
      controller.searchText = '  Acme   Trading ';
      final initial = controller.loadInvoices();
      repository.complete('Acme Trading', 'old', more: true);
      await initial;
      final oldMore = controller.loadMoreInvoices();
      expect(repository.calls.last.after, isNotNull);
      expect(repository.calls.last.search, 'Acme Trading');
      controller.onSearchChanged('  أحمد   عبد ');
      await controller.loadMoreInvoices();
      expect(
        repository.calls.length,
        2,
        reason: 'Do not page an old search while debounce is pending.',
      );
      controller.submitSearch();
      repository.complete('أحمد عبد', 'new', more: true);
      await tester.pump();
      repository.pending['Acme Trading']!.completeError(
        const InvoiceRepositoryException(InvoiceRepositoryError.unavailable),
      );
      await oldMore;
      expect(controller.invoices.single.id, 'new');
      expect(controller.statusRequest, StatusRequest.success);
      expect(controller.isLoadingMore, isFalse);
      final next = controller.loadMoreInvoices();
      repository.complete('أحمد عبد', 'next');
      await next;
      expect(controller.invoices.map((invoice) => invoice.id), ['new', 'next']);
      expect(controller.appliedSearchText, 'أحمد عبد');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'warehouse phrases retain sorting, debounce, Enter and the active search cursor',
    (tester) async {
      final repository = _Items();
      final controller = InventoryDashboardController(
        repository: _Inventory(),
        itemRepository: repository,
        myServices: await _services(),
      );
      addTearDown(controller.onClose);
      controller.itemSort = InventoryItemSort.priceLow;
      controller.itemStatusRequest = StatusRequest.success;
      controller.onItemSearchChanged('w');
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.calls, isEmpty);
      controller.onItemSearchChanged('  Water   Pump ');
      await tester.pump(const Duration(milliseconds: 449));
      expect(repository.calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      repository.complete('Water Pump', 'old', more: true);
      await tester.pump();
      final oldMore = controller.loadMoreItems();
      controller.onItemSearchChanged('  مضخة   ماء ');
      controller.submitItemSearch();
      repository.complete('مضخة ماء', 'new', more: true);
      await tester.pump();
      repository.complete('Water Pump', 'stale-page');
      await oldMore;
      expect(controller.items.single.id, 'new');
      expect(controller.isLoadingMoreItems, isFalse);
      final next = controller.loadMoreItems();
      repository.complete('مضخة ماء', 'next');
      await next;
      expect(controller.items.map((item) => item.id), ['new', 'next']);
      expect(
        repository.calls.every(
          (call) => call.order == 'price' && !call.descending,
        ),
        isTrue,
      );
      expect(repository.calls.last.after, isNotNull);
      expect(repository.calls.last.search, 'مضخة ماء');
      controller.clearItemSearch();
      repository.complete('', 'cleared');
      await tester.pump();
      expect(controller.items.single.id, 'cleared');
      expect(tester.takeException(), isNull);
    },
  );
}

Future<MyServices> _services() async {
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': 'admin',
    'uid': 'admin',
  });
  return MyServices().init();
}

class _Cursor implements FirestorePageCursor {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Call {
  _Call(this.search, this.after, {this.order = '', this.descending = false});
  final String search;
  final FirestorePageCursor? after;
  final String order;
  final bool descending;
}

class _Invoices implements InvoiceRepository {
  final calls = <_Call>[];
  final pending = <String, Completer<FirestorePage<InvoiceModel>>>{};
  @override
  Future<FirestorePage<InvoiceModel>> getInvoicesPage({
    required String companyId,
    InvoiceType? type,
    InvoiceStatus? status,
    PaymentStatus? paymentStatus,
    InvoiceReturnStatus? returnStatus,
    String? salesRepId,
    String? customerId,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchText,
    InvoiceSortField sortField = InvoiceSortField.invoiceDate,
    InvoiceSortDirection sortDirection = InvoiceSortDirection.descending,
    FirestorePageCursor? after,
    int pageSize = 40,
  }) {
    calls.add(_Call(searchText ?? '', after));
    return (pending[searchText ?? ''] = Completer()).future;
  }

  void complete(String search, String id, {bool more = false}) =>
      pending[search]!.complete(
        FirestorePage(
          items: [InvoiceModel.fromMap({}, id: id)],
          cursor: more ? _Cursor() : null,
          hasMore: more,
        ),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Items implements ItemRepository {
  final calls = <_Call>[];
  final pending = <String, Completer<FirestorePage<ItemModel>>>{};
  @override
  Future<FirestorePage<ItemModel>> fetchItemsPage({
    String searchText = '',
    bool? active,
    String orderField = 'nameLower',
    bool descending = false,
    FirestorePageCursor? after,
    int pageSize = 40,
  }) {
    calls.add(
      _Call(searchText, after, order: orderField, descending: descending),
    );
    return (pending[searchText] = Completer()).future;
  }

  void complete(String search, String id, {bool more = false}) =>
      pending[search]!.complete(
        FirestorePage(
          items: [
            ItemModel(
              id: id,
              code: id,
              name: id,
              description: '',
              unit: 'pcs',
              price: 10,
              taxRate: 0,
              active: true,
              deleted: false,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
              createdBy: 'admin',
              currentStock: 30,
              openingStock: 30,
              minStock: 0,
              trackStock: true,
              costPrice: 5,
              warehouseId: ItemModel.defaultWarehouseId,
            ),
          ],
          cursor: more ? _Cursor() : null,
          hasMore: more,
        ),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Inventory implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
