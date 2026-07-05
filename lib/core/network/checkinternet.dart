import 'package:connectivity_plus/connectivity_plus.dart';

typedef ConnectivityLookup = Future<List<ConnectivityResult>> Function();

Future<bool> checkInternet({ConnectivityLookup? lookup}) async {
  try {
    final results = await (lookup ?? Connectivity().checkConnectivity)();
    return results.any((result) => result != ConnectivityResult.none);
  } catch (_) {
    // Connectivity is a preflight hint. If the platform service is
    // unavailable, let Dio perform the request and classify the real error.
    return true;
  }
}
