enum InventoryTransferType {
  warehouseToRep('warehouseToRep'),
  repToWarehouse('repToWarehouse');

  const InventoryTransferType(this.value);
  final String value;
}

enum InventoryTransferStatus {
  draft('draft'),
  confirmed('confirmed'),
  cancelled('cancelled');

  const InventoryTransferStatus(this.value);
  final String value;
}

enum InventorySourceType {
  companyWarehouse('companyWarehouse'),
  salesRep('salesRep');

  const InventorySourceType(this.value);
  final String value;
}

enum RepInventoryDirection {
  inbound('in'),
  outbound('out');

  const RepInventoryDirection(this.value);
  final String value;
}

enum RepInventoryReason {
  warehouseDelivery('warehouseDelivery'),
  warehouseReturn('warehouseReturn'),
  invoiceSale('invoiceSale'),
  salesReturn('salesReturn'),
  openingBalance('openingBalance'),
  correction('correction');

  const RepInventoryReason(this.value);
  final String value;
}

enum RepInventoryReferenceType {
  inventoryTransfer('inventoryTransfer'),
  invoice('invoice'),
  salesReturn('salesReturn');

  const RepInventoryReferenceType(this.value);
  final String value;
}

InventoryTransferType inventoryTransferTypeFromValue(Object? value) =>
    value == InventoryTransferType.repToWarehouse.value
    ? InventoryTransferType.repToWarehouse
    : InventoryTransferType.warehouseToRep;

InventoryTransferStatus inventoryTransferStatusFromValue(Object? value) {
  return switch (value) {
    'confirmed' => InventoryTransferStatus.confirmed,
    'cancelled' => InventoryTransferStatus.cancelled,
    _ => InventoryTransferStatus.draft,
  };
}

InventorySourceType inventorySourceTypeFromValue(Object? value) =>
    value == InventorySourceType.salesRep.value
    ? InventorySourceType.salesRep
    : InventorySourceType.companyWarehouse;

RepInventoryDirection repInventoryDirectionFromValue(Object? value) =>
    value?.toString().toLowerCase() == 'out'
    ? RepInventoryDirection.outbound
    : RepInventoryDirection.inbound;

RepInventoryReason repInventoryReasonFromValue(Object? value) {
  return RepInventoryReason.values.firstWhere(
    (candidate) => candidate.value == value,
    orElse: () => RepInventoryReason.correction,
  );
}

RepInventoryReferenceType repInventoryReferenceTypeFromValue(Object? value) {
  return RepInventoryReferenceType.values.firstWhere(
    (candidate) => candidate.value == value,
    orElse: () => RepInventoryReferenceType.inventoryTransfer,
  );
}
