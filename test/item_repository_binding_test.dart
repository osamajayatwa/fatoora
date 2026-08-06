import 'package:fatoora/app/bindings/initial_binding.dart';
import 'package:fatoora/features/items/binding/items_binding.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  tearDown(Get.reset);

  test('ItemRepository is registered before an item route is opened', () {
    InitialBindings().dependencies();

    expect(Get.isRegistered<ItemRepository>(), isTrue);
  });

  test('item feature registration preserves the repository dependency', () {
    InitialBindings().dependencies();
    registerItemsCoreDependencies();

    expect(Get.isRegistered<ItemRepository>(), isTrue);
  });
}
