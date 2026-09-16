import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server search policy requires two visible characters', () {
    expect(serverSearchTerm(''), '');
    expect(serverSearchTerm('   '), '');
    expect(serverSearchTerm('a'), '');
    expect(serverSearchTerm(' ع '), '');
    expect(serverSearchTerm('ab'), 'ab');
    expect(serverSearchTerm(' عم '), 'عم');
    expect(serverSearchIsTooShort('a'), isTrue);
    expect(serverSearchIsTooShort('عم'), isFalse);
  });

  test('server search debounce is exactly 450 milliseconds', () {
    expect(serverSearchDebounce, const Duration(milliseconds: 450));
  });
}
