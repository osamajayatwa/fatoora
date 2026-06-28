import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/settings/data/models/permission_settings_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';

class EffectiveBusinessPermissions {
  const EffectiveBusinessPermissions({
    required this.isAdmin,
    required this.isSalesRep,
    required this.createCustomers,
    required this.createReceipts,
    required this.createReturns,
    required this.createQuotations,
    required this.editCatalogPrice,
    required this.applyDiscount,
  });

  static const denied = EffectiveBusinessPermissions(
    isAdmin: false,
    isSalesRep: false,
    createCustomers: false,
    createReceipts: false,
    createReturns: false,
    createQuotations: false,
    editCatalogPrice: false,
    applyDiscount: false,
  );

  final bool isAdmin;
  final bool isSalesRep;
  final bool createCustomers;
  final bool createReceipts;
  final bool createReturns;
  final bool createQuotations;
  final bool editCatalogPrice;
  final bool applyDiscount;

  factory EffectiveBusinessPermissions.resolve({
    required String role,
    required bool active,
    required String approvalStatus,
    required PermissionSettingsModel settings,
  }) {
    final isAdmin = role == AuthRepository.adminRole;
    final isSalesRep = role == AuthRepository.salesRepRole;
    final approved =
        approvalStatus == AuthRepository.approvalApproved ||
        (isAdmin && approvalStatus.trim().isEmpty);
    if (!active || !approved || (!isAdmin && !isSalesRep)) return denied;
    if (isAdmin) {
      return const EffectiveBusinessPermissions(
        isAdmin: true,
        isSalesRep: false,
        createCustomers: true,
        createReceipts: true,
        createReturns: true,
        createQuotations: true,
        editCatalogPrice: true,
        applyDiscount: true,
      );
    }
    return EffectiveBusinessPermissions(
      isAdmin: false,
      isSalesRep: true,
      createCustomers: settings.allowSalesRepCreateCustomers,
      createReceipts: settings.allowSalesRepCreateReceipts,
      createReturns: settings.allowSalesRepCreateReturns,
      createQuotations: settings.allowSalesRepCreateQuotations,
      editCatalogPrice: settings.allowSalesRepPriceEdit,
      applyDiscount: settings.allowSalesRepDiscount,
    );
  }

  factory EffectiveBusinessPermissions.fromUser(
    BusinessUserContext user,
    PermissionSettingsModel settings,
  ) {
    return EffectiveBusinessPermissions.resolve(
      role: user.role,
      active: user.active,
      approvalStatus: user.approvalStatus,
      settings: settings,
    );
  }
}

class BusinessPermissionResolver {
  BusinessPermissionResolver({
    required BusinessSettingsResolver settingsResolver,
    BusinessUserContextReader? contextReader,
  }) : _settingsResolver = settingsResolver,
       _contextReader = contextReader ?? BusinessUserContextReader();

  final BusinessSettingsResolver _settingsResolver;
  final BusinessUserContextReader _contextReader;

  Future<EffectiveBusinessPermissions> resolve(String companyId) async {
    try {
      final user = await _contextReader.requireApprovedUser();
      if (companyId.trim().isEmpty || companyId.trim() != user.companyId) {
        return EffectiveBusinessPermissions.denied;
      }
      final settings = await _settingsResolver.loadAppSettings(companyId);
      return EffectiveBusinessPermissions.fromUser(
        user,
        settings.permissionSettings,
      );
    } catch (_) {
      return EffectiveBusinessPermissions.denied;
    }
  }
}
