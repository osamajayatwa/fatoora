import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/services/invoice_totals_service.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_items_table.dart';
import 'package:fatoora/features/invoices/view/widgets/custom_line_editor.dart';
import 'package:fatoora/features/quotations/data/models/quotation_item_model.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_item_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  const totals = InvoiceTotalsService();

  test('legacy and new line schemas round-trip safely', () {
    final legacyCatalog = InvoiceItemSnapshot.fromMap({
      'itemId': 'item-1',
      'itemName': 'Pump',
    });
    expect(legacyCatalog.lineType, InvoiceLineType.catalog);
    expect(legacyCatalog.description, isEmpty);

    final legacyManual = InvoiceItemSnapshot.fromMap({
      'itemId': 'manual-123',
      'itemName': 'Installation',
    });
    expect(legacyManual.lineType, InvoiceLineType.custom);
    expect(legacyManual.isLegacyManual, isTrue);
    expect(legacyManual.toMap().containsKey('lineType'), isFalse);

    final custom = _customLine();
    final restored = InvoiceItemSnapshot.fromMap(custom.toMap());
    expect(restored.lineId, custom.lineId);
    expect(restored.lineType, InvoiceLineType.custom);
    expect(restored.itemId, isNull);
    expect(restored.description, custom.description);
  });

  test('mixed catalog and custom lines use the same financial totals', () {
    final result = totals.calculateInvoice([
      _catalogLine(price: 250),
      _customLine(
        name: 'Installation',
        description: 'At customer site',
        price: 50,
      ),
      _customLine(
        name: 'Maintenance',
        description: 'Preventive service',
        price: 15,
      ),
      _customLine(
        name: 'Parts/service',
        description: 'Miscellaneous',
        price: 5,
      ),
    ]);
    expect(result.subtotal, 320);
    expect(result.grandTotal, 320);
    expect(result.items.where((line) => line.itemId == null), hasLength(3));
  });

  test('quotation and return snapshots preserve custom metadata', () {
    final custom = totals.calculateLine(_customLine());
    final quotation = QuotationItemModel.fromInvoiceItem(custom);
    expect(quotation.toInvoiceItem().toMap(), custom.toMap());

    final salesReturn = SalesReturnItemModel(
      lineId: custom.lineId,
      lineType: custom.lineType,
      itemId: custom.itemId,
      itemName: custom.itemName,
      description: custom.description,
      itemCode: custom.itemCode,
      unit: custom.unit,
      returnedQuantity: 1,
      unitPrice: custom.unitPrice,
      taxPercent: 0,
      subtotal: custom.unitPrice,
      taxAmount: 0,
      total: custom.unitPrice,
      originalInvoiceItemId: 'invoice-1:line:${custom.lineId}',
    );
    final restored = SalesReturnItemModel.fromMap(salesReturn.toMap());
    expect(restored.lineType, InvoiceLineType.custom);
    expect(restored.itemId, isNull);
    expect(restored.description, custom.description);
  });

  testWidgets(
    'desktop permissions keep quantity editable and protect catalog price and discount',
    (tester) async {
      double? capturedQuantity;
      double? capturedUnitPrice;
      double? capturedDiscount;
      await tester.pumpWidget(
        GetMaterialApp(
          translations: MyTranslation(),
          locale: const Locale('en'),
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              child: InvoiceItemsTable(
                items: [_catalogLine(price: 10)],
                editable: true,
                canEditUnitPrice: false,
                canEditDiscount: false,
                onUpdateItem:
                    ({
                      required index,
                      quantity,
                      unitPrice,
                      discount,
                      taxPercent,
                      description,
                      itemName,
                      unit,
                    }) {
                      capturedQuantity = quantity;
                      capturedUnitPrice = unitPrice;
                      capturedDiscount = discount;
                    },
                onRemoveItem: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('catalog-line-quantity-table')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('catalog-line-price-table')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('catalog-line-discount-table')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('catalog-line-quantity-table')),
        '3',
      );
      expect(capturedQuantity, 3);
      expect(capturedUnitPrice, isNull);
      expect(capturedDiscount, isNull);
    },
  );

  testWidgets(
    'desktop custom line price remains editable without catalog price permission',
    (tester) async {
      double? price;
      await tester.pumpWidget(
        GetMaterialApp(
          translations: MyTranslation(),
          locale: const Locale('en'),
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              child: InvoiceItemsTable(
                items: [_customLine()],
                editable: true,
                canEditUnitPrice: false,
                canEditDiscount: false,
                onUpdateItem:
                    ({
                      required index,
                      quantity,
                      unitPrice,
                      discount,
                      taxPercent,
                      description,
                      itemName,
                      unit,
                    }) => price = unitPrice,
                onRemoveItem: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('custom-line-Installation-price-table')),
        '75',
      );
      expect(price, 75);
    },
  );

  testWidgets(
    'custom line editor requires name and description and returns financial fields',
    (tester) async {
      InvoiceItemSnapshot? result;
      await tester.pumpWidget(
        GetMaterialApp(
          translations: MyTranslation(),
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await showCustomLineEditor(
                    context,
                    canApplyDiscount: true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add custom line'));
      await tester.pump();
      expect(find.text('This field is required'), findsNWidgets(2));

      await tester.enterText(_fieldWithLabel('Line name'), 'Installation');
      await tester.enterText(
        _fieldWithLabel('Description'),
        'Commission at site',
      );
      await tester.enterText(_fieldWithLabel('Unit price'), '50');
      await tester.tap(find.text('Add custom line'));
      await tester.pumpAndSettle();
      expect(result?.lineType, InvoiceLineType.custom);
      expect(result?.itemId, isNull);
      expect(result?.itemName, 'Installation');
      expect(result?.description, 'Commission at site');
      expect(result?.unitPrice, 50);
    },
  );

  testWidgets(
    'mobile mixed lines support RTL and large text without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        GetMaterialApp(
          translations: MyTranslation(),
          locale: const Locale('ar'),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: InvoiceItemsTable(
                  items: [_catalogLine(), _customLine()],
                  editable: true,
                  onUpdateItem:
                      ({
                        required index,
                        quantity,
                        unitPrice,
                        discount,
                        taxPercent,
                        description,
                        itemName,
                        unit,
                      }) {},
                  onRemoveItem: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Installation and commissioning'), findsOneWidget);
    },
  );
}

Finder _fieldWithLabel(String label) =>
    find.widgetWithText(TextFormField, label);

InvoiceItemSnapshot _catalogLine({double price = 10}) => InvoiceItemSnapshot(
  lineId: 'catalog-line',
  lineType: InvoiceLineType.catalog,
  itemId: 'item-1',
  itemName: 'Pump',
  description: 'Catalog description snapshot',
  itemCode: 'P-1',
  unit: 'pcs',
  quantity: 1,
  unitPrice: price,
  discount: 0,
  taxPercent: 0,
  subtotal: price,
  taxAmount: 0,
  total: price,
);

InvoiceItemSnapshot _customLine({
  String name = 'Installation',
  String description = 'Installation and commissioning',
  double price = 50,
}) => InvoiceItemSnapshot(
  lineId: 'custom-line-$name',
  lineType: InvoiceLineType.custom,
  itemId: null,
  itemName: name,
  description: description,
  itemCode: '',
  unit: 'service',
  quantity: 1,
  unitPrice: price,
  discount: 0,
  taxPercent: 0,
  subtotal: price,
  taxAmount: 0,
  total: price,
);
