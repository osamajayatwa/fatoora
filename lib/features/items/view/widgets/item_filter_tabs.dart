import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/items/controller/items_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ItemFilterTabs extends StatelessWidget {
  const ItemFilterTabs({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ItemFilter value;
  final ValueChanged<ItemFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFECEFF4),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ItemFilter.values.map((filter) {
          final selected = filter == value;
          final label = switch (filter) {
            ItemFilter.all => 'items_all'.tr,
            ItemFilter.active => 'items_active'.tr,
            ItemFilter.inactive => 'items_inactive'.tr,
          };
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onChanged(filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? AppColor.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x16000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? AppColor.primaryColor : AppColor.darkGrey,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
