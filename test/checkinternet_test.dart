import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fatoora/core/network/checkinternet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports offline when every connectivity result is none', () async {
    final connected = await checkInternet(
      lookup: () async => const [ConnectivityResult.none],
    );

    expect(connected, isFalse);
  });

  test('reports online when any supported transport is available', () async {
    final connected = await checkInternet(
      lookup: () async => const [
        ConnectivityResult.none,
        ConnectivityResult.wifi,
      ],
    );

    expect(connected, isTrue);
  });

  test('allows Dio fallback when connectivity lookup is unavailable', () async {
    final connected = await checkInternet(
      lookup: () async => throw StateError('platform service unavailable'),
    );

    expect(connected, isTrue);
  });
}
