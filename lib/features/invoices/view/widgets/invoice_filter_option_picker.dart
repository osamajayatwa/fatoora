import 'dart:async';

import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/invoices/data/models/invoice_list_query.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

typedef InvoiceFilterOptionLoader =
    Future<List<InvoiceFilterOption>> Function(String searchText);

class InvoiceFilterOptionPicker extends StatefulWidget {
  const InvoiceFilterOptionPicker({
    super.key,
    required this.title,
    required this.searchHint,
    required this.allLabel,
    required this.selected,
    required this.loadOptions,
    required this.onSelected,
  });

  final String title;
  final String searchHint;
  final String allLabel;
  final InvoiceFilterOption? selected;
  final InvoiceFilterOptionLoader loadOptions;
  final ValueChanged<InvoiceFilterOption?> onSelected;

  @override
  State<InvoiceFilterOptionPicker> createState() =>
      _InvoiceFilterOptionPickerState();
}

class _InvoiceFilterOptionPickerState extends State<InvoiceFilterOptionPicker> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  int _requestGeneration = 0;
  bool _loading = true;
  bool _failed = false;
  List<InvoiceFilterOption> _options = const [];

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String searchText) async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final options = await widget.loadOptions(searchText);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _options = options;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _options = const [];
        _loading = false;
        _failed = true;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(value));
  }

  void _select(InvoiceFilterOption? option) {
    Navigator.of(context).pop();
    widget.onSelected(option);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset + 16),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                autofocus: false,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(child: _buildResults()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return Center(
        child: FilledButton.tonalIcon(
          onPressed: () => _load(_searchController.text),
          icon: const Icon(Icons.refresh_rounded),
          label: Text('items_retry'.tr),
        ),
      );
    }
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.select_all_rounded),
          title: Text(widget.allLabel),
          trailing: widget.selected == null
              ? const Icon(Icons.check_rounded, color: AppColor.primaryColor)
              : null,
          onTap: () => _select(null),
        ),
        if (_options.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('no_filter_options'.tr)),
          )
        else
          for (final option in _options)
            ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.person_outline_rounded),
              ),
              title: Text(option.label),
              subtitle: option.subtitle.isEmpty ? null : Text(option.subtitle),
              trailing: widget.selected?.id == option.id
                  ? const Icon(
                      Icons.check_rounded,
                      color: AppColor.primaryColor,
                    )
                  : null,
              onTap: () => _select(option),
            ),
      ],
    );
  }
}
