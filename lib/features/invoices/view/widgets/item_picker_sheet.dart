import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
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

  StatusRequest _statusRequest = StatusRequest.loading;
  List<ItemModel> _items = const [];
  String _errorMessage = 'items_load_error';
  String _searchText = '';

  List<ItemModel> get _visibleItems {
    final query = _searchText.trim().toLowerCase();
    return _items.where((item) {
      if (!item.active || item.deleted) return false;
      if (query.isEmpty) return true;
      return item.name.toLowerCase().contains(query) ||
          item.code.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _statusRequest = StatusRequest.loading);
    try {
      final items = await _repository.fetchItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _statusRequest = StatusRequest.success;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusRequest = StatusRequest.serverfailure;
        _errorMessage = 'items_load_error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return Material(
      color: AppColor.surface,
      borderRadius: BorderRadius.circular(18),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            MediaQuery.viewInsetsOf(context).bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
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
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchText = value),
                decoration: InputDecoration(
                  hintText: 'items_search'.tr,
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.58,
                ),
                child: HandilingDataView(
                  statusrequest: _statusRequest,
                  errorMessage: _errorMessage.tr,
                  retryLabel: 'items_retry'.tr,
                  onRetry: _loadItems,
                  widget: _visibleItems.isEmpty
                      ? Center(child: Text('items_empty'.tr))
                      : ListView.separated(
                          shrinkWrap: true,
                          itemBuilder: (context, index) {
                            final item = _visibleItems[index];
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
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
                          itemCount: _visibleItems.length,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
