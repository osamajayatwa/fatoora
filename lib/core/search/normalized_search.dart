/// Firestore search keyword protocol; mirrored in functions/shared/search_keywords.js.
/// Prefixes start at word boundaries, so multi-word queries stay server-side.
const int searchKeywordLimit = 1024;
const int searchPrefixLength = 80;
const int searchExactLength = 240;

String normalizeSearchText(String value) {
  var text = value
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]'), '')
      .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[\u200E\u200F\u202A-\u202E\u2066-\u2069]'), '')
      .replaceAll('\u200B', ' ');
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  for (var index = 0; index < 10; index++) {
    text = text
        .replaceAll(arabicDigits[index], '$index')
        .replaceAll(persianDigits[index], '$index');
  }
  return text.replaceAll(RegExp(r'[\s\-_/]+'), ' ').trim();
}

List<String> buildNormalizedSearchKeywords(Iterable<String?> values) {
  final keywords = <String>{};
  void add(String value) {
    if (value.isNotEmpty &&
        value.runes.length <= searchExactLength &&
        keywords.length < searchKeywordLimit) {
      keywords.add(value);
    }
  }

  for (final value in values) {
    final legacy = (value ?? '').trim().toLowerCase();
    final normalized = normalizeSearchText(value ?? '');
    final variants = <String>{
      normalized,
      legacy,
      normalized.replaceAll(RegExp(r'[\s\-_/]+'), ' '),
      legacy.replaceAll(RegExp(r'[\s\-_/]+'), ' '),
    };
    for (final variant in variants) {
      add(variant);
      final words = variant
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();
      for (var start = 0; start < words.length; start++) {
        final suffix = words.skip(start).join(' ');
        add(suffix);
        final runes = suffix.runes.take(searchPrefixLength).toList();
        for (var length = 1; length <= runes.length; length++) {
          add(String.fromCharCodes(runes.take(length)).trimRight());
        }
        if (keywords.length == searchKeywordLimit) break;
      }
      if (keywords.length == searchKeywordLimit) break;
    }
    if (keywords.length == searchKeywordLimit) break;
  }
  return keywords.toList()..sort();
}
