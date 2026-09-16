import 'package:fatoora/core/constants/app.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/widgets/fatoora_app_bar.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/core/widgets/responsive_picker_sheet.dart';
import 'package:fatoora/features/admin_dashboard/model/admin_dashboard_models.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/quick_actions_sheet.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  test('app themes preserve the brand and use professional surfaces', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.primary, AppColor.primaryColor);
    expect(dark.scaffoldBackgroundColor, AppColor.darkBackground);
    expect(dark.scaffoldBackgroundColor, isNot(Colors.black));
    expect(dark.colorScheme.surface, AppColor.darkSurface);
  });

  test('Arabic themes use Cairo in light and dark modes', () {
    expect(
      AppTheme.light(fontFamily: 'Cairo').textTheme.bodyMedium?.fontFamily,
      'Cairo',
    );
    expect(
      AppTheme.dark(fontFamily: 'Cairo').textTheme.bodyMedium?.fontFamily,
      'Cairo',
    );
  });

  testWidgets('quick actions open a sheet and return the selected route', (
    tester,
  ) async {
    String? selectedRoute;
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: QuickActionsButton(
            actions: const [
              DashboardQuickAction(
                labelKey: 'dashboard_new_invoice',
                icon: Icons.note_add_outlined,
                route: '/invoices/form',
              ),
            ],
            onSelected: (route) => selectedRoute = route,
          ),
        ),
      ),
    );

    await tester.tap(find.text('dashboard_quick_actions'));
    await tester.pumpAndSettle();
    expect(find.text('dashboard_choose_action'), findsOneWidget);

    await tester.tap(find.text('dashboard_new_invoice'));
    await tester.pumpAndSettle();
    expect(selectedRoute, '/invoices/form');
  });

  testWidgets('quick actions sheet stays usable on narrow screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: QuickActionsButton(
            actions: const [
              DashboardQuickAction(
                labelKey: 'dashboard_new_invoice',
                icon: Icons.note_add_outlined,
                route: '/invoices/form',
              ),
              DashboardQuickAction(
                labelKey: 'dashboard_customers',
                icon: Icons.people_outline,
                route: '/customers',
              ),
            ],
            onSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('dashboard_quick_actions'));
    await tester.pumpAndSettle();

    expect(find.text('dashboard_choose_action'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unified app bar uses the RTL back affordance', (tester) async {
    var wentBack = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(fontFamily: 'Cairo'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: FatooraAppBar(
              title: 'العنوان',
              showBackButton: true,
              onBack: () => wentBack = true,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    expect(wentBack, isTrue);
  });

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets(
      'unified app bar remains usable at 320px and 2x text in $direction',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(fontFamily: 'Cairo'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                appBar: FatooraAppBar(
                  title: direction == TextDirection.rtl
                      ? 'عنوان محاسبي طويل للاختبار'
                      : 'Long accounting screen title',
                  subtitle: direction == TextDirection.rtl
                      ? 'تفاصيل إضافية طويلة'
                      : 'Additional long details',
                  showBackButton: true,
                  actions: const [
                    IconButton(onPressed: null, icon: Icon(Icons.refresh)),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FatooraAppBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('responsive data table card exposes horizontal scrolling', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ResponsiveDataTableCard(
                minWidth: 760,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Amount')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: const [
                    DataRow(
                      cells: [
                        DataCell(
                          BoundedTableText(
                            'Long Arabic اسم العميل',
                            width: 260,
                          ),
                        ),
                        DataCell(BoundedTableText('JOD 100.000', width: 160)),
                        DataCell(
                          SizedBox(
                            width: 120,
                            child: Icon(Icons.picture_as_pdf_outlined),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets(
      'business page header stacks safely at 320px and 2x text in $direction',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          GetMaterialApp(
            theme: AppTheme.light(fontFamily: 'Cairo'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: BusinessPageHeader(
                      title: 'Long accounting page title',
                      subtitle:
                          'A detailed subtitle that may wrap onto two lines',
                      trailing: BusinessPrimaryActionButton(
                        label: 'Create a new record',
                        icon: Icons.add_rounded,
                        onPressed: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(BusinessPageHeader), findsOneWidget);
        expect(find.byType(BusinessPrimaryActionButton), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('shared loading and empty states use consistent controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              const BusinessEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Nothing here',
                message: 'Try changing the filters',
              ),
              BusinessLoadMoreButton(loading: true, onPressed: () {}),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Try changing the filters'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'picker sheet scrolls instead of overflowing in keyboard-height viewport',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 240));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(412, 240),
              textScaler: TextScaler.linear(2),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: 142,
                    child: ResponsivePickerSheet(
                      header: const Text('اختيار عنصر من القائمة'),
                      search: const TextField(
                        decoration: InputDecoration(labelText: 'بحث'),
                      ),
                      body: ListView(
                        children: const [
                          ListTile(title: Text('العنصر الأول')),
                          ListTile(title: Text('العنصر الثاني')),
                        ],
                      ),
                      footer: const OutlinedButton(
                        onPressed: null,
                        child: Text('إضافة عنصر جديد'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ResponsivePickerSheet), findsOneWidget);
      expect(find.byType(ListView), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
