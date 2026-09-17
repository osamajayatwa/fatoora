import 'dart:async';

import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/core/widgets/responsive_picker_sheet.dart';
import 'package:fatoora/features/items/binding/items_binding.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

Future<ItemModel?> showInvoiceItemPicker(BuildContext context) {
  registerItemsCoreDependencies();
  final content = const InvoiceItemPickerSheet();
  final wide = MediaQuery.sizeOf(context).width >= 760;
  if (wide) {
    return Get.dialog<ItemModel>(
      Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: content,
        ),
      ),
    );
  }
  return Get.bottomSheet<ItemModel>(
    content,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
  );
}

class InvoiceItemPickerSheet extends StatefulWidget {
  const InvoiceItemPickerSheet({super.key});

  @override
  State<InvoiceItemPickerSheet> createState() => _InvoiceItemPickerSheetState();
}

class _InvoiceItemPickerSheetState extends State<InvoiceItemPickerSheet> {
  final ItemRepository _repository = Get.find<ItemRepository>();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StatusRequest _statusRequest = StatusRequest.loading;
  List<ItemModel> _items = const [];
  String _errorMessage = 'items_load_error';
  String _searchText = '';
  String _appliedSearch = '';
  FirestorePageCursor? _cursor;
  Timer? _debounce;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadItems();
  }

  Future<void> _loadItems({bool append = false}) async {
    if (append && (_isLoadingMore || !_hasMore || _cursor == null)) return;
    final generation = append ? _generation : ++_generation;
    final requestedSearch = serverSearchTerm(_searchText);
    if (append) {
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _statusRequest = StatusRequest.loading;
        _cursor = null;
        _hasMore = false;
      });
    }
    try {
      final page = await _repository.fetchItemsPage(
        searchText: requestedSearch,
        active: true,
        orderField: 'nameLower',
        descending: false,
        after: append ? _cursor : null,
        pageSize: 30,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = append ? [..._items, ...page.items] : page.items;
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _appliedSearch = requestedSearch;
        _statusRequest = StatusRequest.success;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!append) _statusRequest = StatusRequest.serverfailure;
        _errorMessage = 'items_load_error';
      });
    } finally {
      if (mounted && generation == _generation && _isLoadingMore) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchText = value;
    _debounce?.cancel();
    _generation++;
    final next = serverSearchTerm(value);
    if (next.isEmpty) {
      if (_appliedSearch.isNotEmpty) _loadItems();
      return;
    }
    _debounce = Timer(serverSearchDebounce, _loadItems);
  }

  void _submitSearch(String _) {
    _debounce?.cancel();
    _loadItems();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 350) {
      _loadItems(append: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return ResponsivePickerSheet(
      header: Row(
        children: [
          Expanded(
            child: Text(
              'items_title'.tr,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: Get.back<void>,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      search: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        onSubmitted: _submitSearch,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'items_search'.tr,
          prefixIcon: const Icon(Icons.search_rounded),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      body: HandilingDataView(
        statusrequest: _statusRequest,
        errorMessage: _errorMessage.tr,
        retryLabel: 'items_retry'.tr,
        onRetry: _loadItems,
        widget: _items.isEmpty
            ? Center(child: Text('items_empty'.tr))
            : ListView.separated(
                controller: _scrollController,
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final item = _items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFF4F6FA),
                      child: Icon(Icons.inventory_2_outlined),
                    ),
                    title: Text(item.name),
                    subtitle: Text(
                      [
                        item.code,
                        item.unit,
                        '${item.taxRate}% ${'tax'.tr}',
                        item.trackStock
                            ? '${'current_stock'.tr}: ${NumberFormat('#,##0.###').format(item.currentStock)}'
                            : 'track_stock_disabled'.tr,
                      ].where((value) => value.isNotEmpty).join(' / '),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(currency.format(item.price)),
                        if (item.trackStock)
                          Text(
                            item.isOutOfStock
                                ? 'out_of_stock'.tr
                                : item.isLowStock
                                ? 'low_stock'.tr
                                : 'available_quantity'.tr,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: item.isOutOfStock
                                      ? AppColor.error
                                      : item.isLowStock
                                      ? const Color(0xFFFFA43A)
                                      : AppColor.success,
                                ),
                          ),
                      ],
                    ),
                    onTap: () => Get.back<ItemModel>(result: item),
                  );
                },
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemCount: _items.length + (_isLoadingMore ? 1 : 0),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }
}
