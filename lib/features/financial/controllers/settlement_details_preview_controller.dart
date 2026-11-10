import 'dart:async';
import 'package:fatoora/features/financial/data/models/settlement_details.dart';
import 'package:get/get.dart';

enum SettlementPreviewState {
  idle,
  loading,
  incomplete,
  verified,
  blocked,
  coverageIncomplete,
  error,
  expired,
  denied,
}

/// Presentation state only. Retains the last valid page on retry and never
/// publishes certified totals from an incomplete or failed page sequence.
final class SettlementDetailsPreviewController extends GetxController {
  SettlementDetailsPreviewController(this.fixtures)
    : assembly = SettlementDetailsAssembly(
        companyId: fixtures.companyId,
        representativeId: fixtures.representativeId,
        settlementId: fixtures.settlementId,
        origin: fixtures.origin,
      );
  final SettlementDetailsSource fixtures;
  SettlementDetailsAssembly assembly;
  Timer? _expiry;
  StreamSubscription<SettlementReadFailure>? _invalidations;
  @override
  void onInit() {
    super.onInit();
    fixtures.reset();
    _invalidations = fixtures.invalidations.listen((failure) {
      if (!isClosed) {
        invalidate(
          failure == SettlementReadFailure.denied
              ? SettlementPreviewState.denied
              : SettlementPreviewState.expired,
        );
        update();
      }
    });
  }

  SettlementPreviewState state = SettlementPreviewState.idle;
  int _generation = 0;
  bool loadingAll = false;
  Future<void> loadAll() async {
    if (loadingAll || !canLoad || isClosed) return;
    loadingAll = true;
    update();
    try {
      while (canLoad && !isClosed) {
        await loadNext();
        if ([
          SettlementPreviewState.error,
          SettlementPreviewState.expired,
          SettlementPreviewState.denied,
          SettlementPreviewState.coverageIncomplete,
        ].contains(state)) {
          break;
        }
      }
    } finally {
      loadingAll = false;
      if (!isClosed) update();
    }
  }

  Map<String, BigInt>? get totals =>
      state == SettlementPreviewState.verified && !fixtures.expired
      ? assembly.certifiedTotals
      : null;
  bool get canLoad =>
      !assembly.complete &&
      state != SettlementPreviewState.loading &&
      state != SettlementPreviewState.expired &&
      state != SettlementPreviewState.denied &&
      state != SettlementPreviewState.coverageIncomplete;
  Future<void> loadNext() async {
    if (!canLoad || isClosed) return;
    if (fixtures.coverageIncomplete) {
      state = SettlementPreviewState.coverageIncomplete;
      update();
      return;
    }
    final generation = _generation;
    state = SettlementPreviewState.loading;
    update();
    try {
      final source = fixtures;
      final pages = source is SettlementDetailsBatchSource
          ? await source.readBatch(assembly.loadedPages)
          : [await source.read(assembly.loadedPages)];
      if (isClosed || generation != _generation) return;
      try {
        assembly.addBatch(pages);
      } on FormatException {
        throw const SettlementReadException(SettlementReadFailure.corrupt);
      }
      _expiry?.cancel();
      final expires = fixtures.expiresAtMillis;
      if (expires != null) {
        _expiry = Timer(
          Duration(
            milliseconds: (expires - DateTime.now().millisecondsSinceEpoch)
                .clamp(0, 360000),
          ),
          () {
            if (!isClosed) {
              invalidate(SettlementPreviewState.expired);
              update();
            }
          },
        );
      }
      state = !assembly.complete
          ? SettlementPreviewState.incomplete
          : assembly.verified
          ? SettlementPreviewState.verified
          : SettlementPreviewState.blocked;
    } on SettlementReadException catch (error) {
      if (isClosed || generation != _generation) return;
      if (error.failure == SettlementReadFailure.denied) {
        invalidate(SettlementPreviewState.denied);
      } else if (error.failure == SettlementReadFailure.expired ||
          error.failure == SettlementReadFailure.corrupt) {
        invalidate(SettlementPreviewState.expired);
      } else {
        state = fixtures.coverageIncomplete
            ? SettlementPreviewState.coverageIncomplete
            : SettlementPreviewState.error;
      }
    } catch (_) {
      if (isClosed || generation != _generation) return;
      state = SettlementPreviewState.error;
    }
    update();
  }

  SettlementDetailsReport reportForPdf() {
    if (fixtures.expired ||
        state != SettlementPreviewState.verified &&
            state != SettlementPreviewState.blocked) {
      throw StateError('Complete validated detail pages required for PDF');
    }
    return assembly.finish();
  }

  void invalidate(SettlementPreviewState next) {
    _generation++;
    _expiry?.cancel();
    assembly = SettlementDetailsAssembly(
      companyId: fixtures.companyId,
      representativeId: fixtures.representativeId,
      settlementId: fixtures.settlementId,
      origin: fixtures.origin,
    );
    state = next;
  }

  Future<void> restart() async {
    if (state == SettlementPreviewState.loading) return;
    fixtures.reset();
    invalidate(SettlementPreviewState.idle);
    await loadNext();
  }

  @override
  void onClose() {
    _generation++;
    _expiry?.cancel();
    _invalidations?.cancel();
    fixtures.reset();
    super.onClose();
  }
}
