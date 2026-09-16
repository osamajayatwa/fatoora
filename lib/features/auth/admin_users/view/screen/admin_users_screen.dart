import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/auth/admin_users/controller/admin_users_controller.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AdminUsersController>(
      initState: (state) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (state.controller != null) {
            state.controller!.selectTab(initialTab);
          }
        });
      },
      builder: (controller) {
        final users = switch (controller.selectedTab) {
          0 => controller.pendingUsers,
          1 => controller.salesReps,
          _ => controller.admins,
        };
        final pending = controller.selectedTab == 0;
        final adminList = controller.selectedTab == 2;
        return BusinessShell(
          title: 'admin_users'.tr,
          child: HandilingDataView(
            statusrequest: controller.statusRequest,
            errorMessage: controller.loadErrorMessageKey.tr,
            retryLabel: 'items_retry'.tr,
            onRetry: controller.loadUsers,
            widget: RefreshIndicator(
              color: AppColor.primaryColor,
              onRefresh: controller.refreshUsers,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1220),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Header(controller: controller),
                            const SizedBox(height: 18),
                            _TabSelector(controller: controller),
                            const SizedBox(height: 18),
                            if (users.isEmpty)
                              _EmptyUsers(
                                messageKey: controller.selectedTab == 0
                                    ? 'admin_users_no_pending'
                                    : controller.selectedTab == 1
                                    ? 'admin_users_no_sales_reps'
                                    : 'admin_users_no_admins',
                              )
                            else if (compact)
                              _UsersCards(
                                users: users,
                                pending: pending,
                                adminList: adminList,
                                controller: controller,
                              )
                            else
                              _UsersTable(
                                users: users,
                                pending: pending,
                                adminList: adminList,
                                controller: controller,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final AdminUsersController controller;

  @override
  Widget build(BuildContext context) {
    return BusinessPageHeader(
      title: 'admin_users'.tr,
      subtitle: 'admin_users_subtitle'.tr,
      trailing: BusinessSecondaryActionButton(
        onPressed: controller.loadUsers,
        icon: Icons.refresh_rounded,
        label: 'dashboard_refresh'.tr,
      ),
    );
  }
}

class _TabSelector extends StatelessWidget {
  const _TabSelector({required this.controller});

  final AdminUsersController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ChoiceChip(
          selected: controller.selectedTab == 0,
          onSelected: (_) => controller.selectTab(0),
          label: Text(
            '${'admin_users_pending'.tr} (${controller.pendingUsers.length})',
          ),
        ),
        ChoiceChip(
          selected: controller.selectedTab == 1,
          onSelected: (_) => controller.selectTab(1),
          label: Text(
            '${'admin_users_sales_reps'.tr} (${controller.salesReps.length})',
          ),
        ),
        ChoiceChip(
          selected: controller.selectedTab == 2,
          onSelected: (_) => controller.selectTab(2),
          label: Text(
            '${'admin_users_admins'.tr} (${controller.admins.length})',
          ),
        ),
      ],
    );
  }
}

class _UsersCards extends StatelessWidget {
  const _UsersCards({
    required this.users,
    required this.pending,
    required this.adminList,
    required this.controller,
  });

  final List<AppUserModel> users;
  final bool pending;
  final bool adminList;
  final AdminUsersController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final user in users) ...[
          _UserCard(
            user: user,
            pending: pending,
            adminList: adminList,
            controller: controller,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.pending,
    required this.adminList,
    required this.controller,
  });

  final AppUserModel user;
  final bool pending;
  final bool adminList;
  final AdminUsersController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColor.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4E8EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColor.primaryLight,
                  child: Text(_initials(user.name)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name.isEmpty ? user.email : user.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppColor.secondaryColor,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        user.email,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
                      ),
                    ],
                  ),
                ),
                _StatusChip(user: user),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _Meta(icon: Icons.phone_outlined, text: user.phone),
                _RoleChip(user: user),
                _Meta(
                  icon: Icons.calendar_today_outlined,
                  text: DateFormat.yMd().format(user.createdAt),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _UserActions(
              user: user,
              pending: pending,
              adminList: adminList,
              controller: controller,
            ),
          ],
        ),
      ),
    );
  }
}

class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.users,
    required this.pending,
    required this.adminList,
    required this.controller,
  });

  final List<AppUserModel> users;
  final bool pending;
  final bool adminList;
  final AdminUsersController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColor.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4E8EF)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColor.secondaryColor,
            fontWeight: FontWeight.w800,
          ),
          dataTextStyle: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColor.secondaryColor),
          columns: [
            DataColumn(label: Text('Name'.tr)),
            DataColumn(label: Text('Email'.tr)),
            DataColumn(label: Text('Phone'.tr)),
            DataColumn(label: Text('admin_users_role'.tr)),
            DataColumn(label: Text('admin_users_status'.tr)),
            DataColumn(label: Text('items_created_at'.tr)),
            DataColumn(label: Text('actions'.tr)),
          ],
          rows: users
              .map(
                (user) => DataRow(
                  cells: [
                    DataCell(_NameCell(user: user)),
                    DataCell(Text(user.email)),
                    DataCell(Text(user.phone.isEmpty ? '-' : user.phone)),
                    DataCell(_RoleChip(user: user)),
                    DataCell(_StatusChip(user: user)),
                    DataCell(Text(DateFormat.yMd().format(user.createdAt))),
                    DataCell(
                      _UserActions(
                        user: user,
                        pending: pending,
                        adminList: adminList,
                        controller: controller,
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.user});

  final AppUserModel user;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Text(
        user.name.isEmpty ? user.email : user.name,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _UserActions extends StatelessWidget {
  const _UserActions({
    required this.user,
    required this.pending,
    required this.adminList,
    required this.controller,
  });

  final AppUserModel user;
  final bool pending;
  final bool adminList;
  final AdminUsersController controller;

  @override
  Widget build(BuildContext context) {
    final loading = controller.activeActionUid == user.uid;
    if (loading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (pending) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => controller.approveUser(user),
            icon: const Icon(Icons.check_rounded),
            label: Text('admin_users_approve_as_sales_rep'.tr),
          ),
          FilledButton.icon(
            onPressed: () => controller.approveUserAsAdmin(user),
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.secondaryColor,
            ),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: Text('admin_users_approve_as_admin'.tr),
          ),
          OutlinedButton.icon(
            onPressed: () => controller.rejectUser(user),
            icon: const Icon(Icons.close_rounded),
            label: Text('admin_users_reject'.tr),
          ),
        ],
      );
    }
    if (adminList && controller.isCurrentUser(user)) {
      return Chip(
        avatar: const Icon(Icons.verified_user_outlined, size: 18),
        label: Text('admin_users_current_account'.tr),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        IconButton.filledTonal(
          tooltip: 'items_edit'.tr,
          onPressed: () => _showEditDialog(context, controller, user),
          icon: const Icon(Icons.edit_outlined),
        ),
        if (adminList)
          IconButton.filledTonal(
            tooltip: 'admin_users_demote'.tr,
            onPressed: () => controller.demoteToSalesRep(user),
            icon: const Icon(Icons.person_outline_rounded),
          )
        else
          IconButton.filledTonal(
            tooltip: 'admin_users_promote'.tr,
            onPressed: () => controller.promoteToAdmin(user),
            icon: const Icon(Icons.admin_panel_settings_outlined),
          ),
        if (user.active)
          IconButton.filledTonal(
            tooltip: 'admin_users_deactivate'.tr,
            onPressed: () => controller.deactivateUser(user),
            icon: const Icon(Icons.block_outlined),
          )
        else
          IconButton.filledTonal(
            tooltip: 'admin_users_activate'.tr,
            onPressed: () => controller.activateUser(user),
            icon: const Icon(Icons.check_circle_outline),
          ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.user});

  final AppUserModel user;

  @override
  Widget build(BuildContext context) {
    final admin = user.isAdmin;
    final color = admin ? AppColor.secondaryColor : AppColor.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        (admin ? 'admin_users_role_admin' : 'admin_users_role_sales_rep').tr,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.user});

  final AppUserModel user;

  @override
  Widget build(BuildContext context) {
    final label = user.isPending
        ? 'admin_users_pending'
        : user.active
        ? 'items_active'
        : 'items_inactive';
    final color = user.isPending
        ? const Color(0xFFFFA43A)
        : user.active
        ? AppColor.success
        : AppColor.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.tr,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColor.grey),
        const SizedBox(width: 5),
        Text(
          text.isEmpty ? '-' : text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColor.secondaryColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EmptyUsers extends StatelessWidget {
  const _EmptyUsers({required this.messageKey});

  final String messageKey;

  @override
  Widget build(BuildContext context) {
    return BusinessEmptyState(
      icon: Icons.manage_accounts_outlined,
      title: messageKey.tr,
    );
  }
}

Future<void> _showEditDialog(
  BuildContext context,
  AdminUsersController controller,
  AppUserModel user,
) async {
  final nameController = TextEditingController(text: user.name);
  final phoneController = TextEditingController(text: user.phone);
  try {
    final saved = await Get.dialog<bool>(
      AlertDialog(
        title: Text(
          (user.isAdmin
                  ? 'admin_users_edit_admin'
                  : 'admin_users_edit_sales_rep')
              .tr,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: 'Name'.tr),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: 'Phone'.tr),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('dashboard_cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('items_save'.tr),
          ),
        ],
      ),
    );
    if (saved == true) {
      await controller.updateUser(
        user,
        nameController.text,
        phoneController.text,
      );
    }
  } finally {
    nameController.dispose();
    phoneController.dispose();
  }
}

String _initials(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return 'U';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
