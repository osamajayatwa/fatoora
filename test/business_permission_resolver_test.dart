import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/settings/data/models/permission_settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  EffectiveBusinessPermissions salesRep(PermissionSettingsModel settings) {
    return EffectiveBusinessPermissions.resolve(
      role: AuthRepository.salesRepRole,
      active: true,
      approvalStatus: AuthRepository.approvalApproved,
      settings: settings,
    );
  }

  test('missing-settings defaults preserve current sales-rep behavior', () {
    final permissions = salesRep(PermissionSettingsModel.defaults);

    expect(permissions.createCustomers, isTrue);
    expect(permissions.createReceipts, isTrue);
    expect(permissions.createReturns, isTrue);
    expect(permissions.createQuotations, isTrue);
    expect(permissions.editCatalogPrice, isTrue);
    expect(permissions.applyDiscount, isTrue);
  });

  test('sales-rep customer creation can be disabled', () {
    final permissions = salesRep(
      PermissionSettingsModel.defaults.copyWith(
        allowSalesRepCreateCustomers: false,
      ),
    );
    expect(permissions.createCustomers, isFalse);
  });

  test('sales-rep receipt creation can be disabled', () {
    final permissions = salesRep(
      PermissionSettingsModel.defaults.copyWith(
        allowSalesRepCreateReceipts: false,
      ),
    );
    expect(permissions.createReceipts, isFalse);
  });

  test('sales-rep return creation can be disabled', () {
    final permissions = salesRep(
      PermissionSettingsModel.defaults.copyWith(
        allowSalesRepCreateReturns: false,
      ),
    );
    expect(permissions.createReturns, isFalse);
  });

  test('sales-rep quotation creation can be disabled', () {
    final permissions = salesRep(
      PermissionSettingsModel.defaults.copyWith(
        allowSalesRepCreateQuotations: false,
      ),
    );
    expect(permissions.createQuotations, isFalse);
  });

  test('sales-rep price editing and discounts can be disabled', () {
    final permissions = salesRep(
      PermissionSettingsModel.defaults.copyWith(
        allowSalesRepPriceEdit: false,
        allowSalesRepDiscount: false,
      ),
    );
    expect(permissions.editCatalogPrice, isFalse);
    expect(permissions.applyDiscount, isFalse);
  });

  test('admin remains allowed when every sales-rep toggle is disabled', () {
    final disabled = PermissionSettingsModel.defaults.copyWith(
      allowSalesRepCreateCustomers: false,
      allowSalesRepCreateReceipts: false,
      allowSalesRepCreateReturns: false,
      allowSalesRepCreateQuotations: false,
      allowSalesRepPriceEdit: false,
      allowSalesRepDiscount: false,
    );
    final permissions = EffectiveBusinessPermissions.resolve(
      role: AuthRepository.adminRole,
      active: true,
      approvalStatus: AuthRepository.approvalApproved,
      settings: disabled,
    );

    expect(permissions.createCustomers, isTrue);
    expect(permissions.createReceipts, isTrue);
    expect(permissions.createReturns, isTrue);
    expect(permissions.createQuotations, isTrue);
    expect(permissions.editCatalogPrice, isTrue);
    expect(permissions.applyDiscount, isTrue);
  });

  test('pending and inactive users receive no business permissions', () {
    final pending = EffectiveBusinessPermissions.resolve(
      role: AuthRepository.salesRepRole,
      active: true,
      approvalStatus: AuthRepository.approvalPending,
      settings: PermissionSettingsModel.defaults,
    );
    final inactive = EffectiveBusinessPermissions.resolve(
      role: AuthRepository.salesRepRole,
      active: false,
      approvalStatus: AuthRepository.approvalApproved,
      settings: PermissionSettingsModel.defaults,
    );

    expect(pending.createCustomers, isFalse);
    expect(pending.createReceipts, isFalse);
    expect(inactive.createReturns, isFalse);
    expect(inactive.createQuotations, isFalse);
  });
}
