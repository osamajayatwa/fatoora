import 'package:fatoora/core/firebase/pending_posting_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const payload = {
    'companyId': 'company',
    'customerId': 'customer',
    'amount': 10,
  };

  test(
    'timeout and readback retry retain a durable key without posting twice',
    () async {
      final key = await PendingPostingKeys.acquire('receipt', 'rep', payload);
      expect(await PendingPostingKeys.acquire('receipt', 'rep', payload), key);
      final preferences = await SharedPreferences.getInstance();
      SharedPreferences.setMockInitialValues({
        for (final name in preferences.getKeys()) name: preferences.get(name)!,
      });
      expect(await PendingPostingKeys.acquire('receipt', 'rep', payload), key);
      await PendingPostingKeys.complete('receipt', 'rep', payload, key);
      expect(
        await PendingPostingKeys.acquire('receipt', 'rep', payload),
        isNot(key),
      );
    },
  );
  test('simultaneous identical requests share a single key', () async {
    final keys = await Future.wait(
      List.generate(
        5,
        (_) => PendingPostingKeys.acquire('expense', 'rep', payload),
      ),
    );
    expect(keys.toSet(), hasLength(1));
  });
  test(
    'keys are scoped to actor, company, operation and exact request',
    () async {
      final keys = await Future.wait([
        PendingPostingKeys.acquire('receipt', 'rep-a', payload),
        PendingPostingKeys.acquire('receipt', 'rep-b', payload),
        PendingPostingKeys.acquire('expense', 'rep-a', payload),
        PendingPostingKeys.acquire('receipt', 'rep-a', {
          ...payload,
          'amount': 11,
        }),
        PendingPostingKeys.acquire('receipt', 'rep-a', {
          ...payload,
          'companyId': 'other',
        }),
      ]);
      expect(keys.toSet(), hasLength(5));
    },
  );
  test(
    'canonical map ordering is stable and stored data excludes customer details',
    () async {
      final first = await PendingPostingKeys.acquire('receipt', 'rep', payload);
      final reordered = {
        'amount': 10,
        'customerId': 'customer',
        'companyId': 'company',
      };
      expect(
        await PendingPostingKeys.acquire('receipt', 'rep', reordered),
        first,
      );
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys().single, startsWith('pending_posting_v1_'));
      expect(preferences.getKeys().single, isNot(contains('customer')));
    },
  );
}
