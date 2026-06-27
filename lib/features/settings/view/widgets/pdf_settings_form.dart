import 'package:fatoora/features/settings/controllers/admin_settings_controller.dart';
import 'package:fatoora/features/settings/view/widgets/settings_switch_tile.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PdfSettingsForm extends StatelessWidget {
  const PdfSettingsForm({super.key, required this.controller});

  final AdminSettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsSwitchTile(
          title: 'settings_show_logo'.tr,
          value: controller.showLogo,
          onChanged: controller.setShowLogo,
        ),
        SettingsSwitchTile(
          title: 'settings_show_company_info'.tr,
          value: controller.showCompanyInfo,
          onChanged: controller.setShowCompanyInfo,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            value: controller.pdfLanguageMode,
            decoration: InputDecoration(
              labelText: 'settings_pdf_language_mode'.tr,
            ),
            items: [
              DropdownMenuItem(
                value: 'app_language',
                child: Text('settings_app_language'.tr),
              ),
              DropdownMenuItem(value: 'ar', child: Text('settings_arabic'.tr)),
              DropdownMenuItem(value: 'en', child: Text('settings_english'.tr)),
            ],
            onChanged: controller.setPdfLanguageMode,
          ),
        ),
        _text(controller.invoiceFooterController, 'settings_invoice_footer'),
        _text(controller.quotationTermsController, 'settings_quotation_terms'),
        _text(controller.receiptFooterController, 'settings_receipt_footer'),
        _text(
          controller.statementFooterController,
          'settings_statement_footer',
        ),
        _text(controller.defaultNotesController, 'settings_default_notes'),
      ],
    );
  }

  Widget _text(TextEditingController textController, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: textController,
        maxLines: 2,
        decoration: InputDecoration(labelText: key.tr),
      ),
    );
  }
}
