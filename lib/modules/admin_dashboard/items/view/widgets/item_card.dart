import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/data/models/item_model.dart';
import 'package:fatoora/modules/admin_dashboard/items/view/widgets/item_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item, required this.onTap});

  final ItemModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: AppColor.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: Color(0xFFE5E8EF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColor.primaryLight.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: AppColor.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: AppColor.secondaryColor,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ItemStatusBadge(active: item.active),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                item.description.isEmpty ? '—' : item.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColor.darkGrey,
                  height: 1.45,
                ),
              ),
              const Spacer(),
              const Divider(color: Color(0xFFECEEF3)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _CardValue(
                      label: 'items_price'.tr,
                      value:
                          '${NumberFormat('#,##0.00').format(item.price)} ${'items_jod'.tr}',
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 34,
                    color: const Color(0xFFE8EAF0),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _CardValue(label: 'items_unit'.tr, value: item.unit),
                  ),
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: AppColor.grey,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardValue extends StatelessWidget {
  const _CardValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColor.grey),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColor.secondaryColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
