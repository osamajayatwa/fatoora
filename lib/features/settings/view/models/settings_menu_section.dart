import 'package:fatoora/app/routes/app_routes.dart';
import 'package:flutter/material.dart';

class SettingsMenuSection {
  const SettingsMenuSection({
    required this.titleKey,
    required this.subtitleKey,
    required this.icon,
    required this.route,
  });

  final String titleKey;
  final String subtitleKey;
  final IconData icon;
  final String route;
}

List<SettingsMenuSection> settingsMenuSections({required bool isAdmin}) {
  if (!isAdmin) return _sharedSections;
  return [..._adminSections, ..._sharedSections];
}

const _adminSections = [
  SettingsMenuSection(
    titleKey: 'settings_company',
    subtitleKey: 'settings_company_subtitle',
    icon: Icons.business_outlined,
    route: AppRoute.companySettings,
  ),
  SettingsMenuSection(
    titleKey: 'settings_documents',
    subtitleKey: 'settings_documents_subtitle',
    icon: Icons.description_outlined,
    route: AppRoute.documentSettings,
  ),
  SettingsMenuSection(
    titleKey: 'settings_inventory',
    subtitleKey: 'settings_inventory_subtitle',
    icon: Icons.warehouse_outlined,
    route: AppRoute.inventorySettings,
  ),
  SettingsMenuSection(
    titleKey: 'settings_pdf',
    subtitleKey: 'settings_pdf_subtitle',
    icon: Icons.picture_as_pdf_outlined,
    route: AppRoute.pdfSettings,
  ),
  SettingsMenuSection(
    titleKey: 'settings_permissions',
    subtitleKey: 'settings_permissions_subtitle',
    icon: Icons.admin_panel_settings_outlined,
    route: AppRoute.permissionSettings,
  ),
  SettingsMenuSection(
    titleKey: 'settings_jofotara',
    subtitleKey: 'settings_jofotara_subtitle',
    icon: Icons.lock_clock_outlined,
    route: AppRoute.jofotaraSettings,
  ),
];

const _sharedSections = [
  SettingsMenuSection(
    titleKey: 'settings_profile',
    subtitleKey: 'settings_profile_subtitle',
    icon: Icons.person_outline_rounded,
    route: AppRoute.profileSettings,
  ),
  SettingsMenuSection(
    titleKey: 'settings_preferences',
    subtitleKey: 'settings_preferences_subtitle',
    icon: Icons.tune_rounded,
    route: AppRoute.appPreferencesSettings,
  ),
  SettingsMenuSection(
    titleKey: 'settings_account',
    subtitleKey: 'settings_account_subtitle',
    icon: Icons.info_outline_rounded,
    route: AppRoute.accountSettings,
  ),
];
