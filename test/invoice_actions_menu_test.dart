import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_actions_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  tearDown(Get.reset);

  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets(
      'invoice menu exposes a disabled tax conversion in ${locale.languageCode}',
      (tester) async {
        var callbackCount = 0;
        await tester.pumpWidget(
          GetMaterialApp(
            locale: locale,
            translations: MyTranslation(),
            home: Scaffold(
              body: InvoiceActionsMenu(
                compact: false,
                showView: true,
                showCreateSalesReturn: true,
                showDelete: true,
                canEdit: true,
                canCreateSalesReturn: true,
                canDelete: true,
                onView: () => callbackCount++,
                onEdit: () => callbackCount++,
                onCreateSalesReturn: () => callbackCount++,
                onPrint: () => callbackCount++,
                onDelete: () => callbackCount++,
              ),
            ),
          ),
        );

        final actionLabel = locale.languageCode == 'ar'
            ? 'الإجراءات'
            : 'Actions';
        final convertLabel = locale.languageCode == 'ar'
            ? 'تحويل إلى فاتورة ضريبية'
            : 'Convert to Tax Invoice';
        expect(find.text(actionLabel), findsOneWidget);

        await tester.tap(find.byType(InvoiceActionsMenu));
        await tester.pumpAndSettle();
        expect(find.text(convertLabel), findsOneWidget);
        final disabledItems = find.byWidgetPredicate(
          (widget) => widget is PopupMenuItem && !widget.enabled,
        );
        expect(disabledItems, findsOneWidget);

        await tester.tap(find.text(convertLabel));
        await tester.pump();
        expect(callbackCount, 0);
        expect(find.text(convertLabel), findsOneWidget);
      },
    );
  }

  testWidgets('compact invoice menu invokes enabled actions', (tester) async {
    var viewed = false;
    await tester.pumpWidget(
      GetMaterialApp(
        locale: const Locale('en'),
        translations: MyTranslation(),
        home: Scaffold(
          body: InvoiceActionsMenu(showView: true, onView: () => viewed = true),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invoice details'));
    await tester.pumpAndSettle();
    expect(viewed, isTrue);
  });
}
