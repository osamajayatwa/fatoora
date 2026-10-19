const Duration serverSearchDebounce = Duration(milliseconds: 450);
const int serverSearchMinimumLength = 2;

String serverSearchTerm(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed.runes.length >= serverSearchMinimumLength ? trimmed : '';
}

bool serverSearchIsTooShort(String value) {
  final length = value.trim().replaceAll(RegExp(r'\s+'), ' ').runes.length;
  return length > 0 && length < serverSearchMinimumLength;
}
