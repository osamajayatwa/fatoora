const Duration serverSearchDebounce = Duration(milliseconds: 450);
const int serverSearchMinimumLength = 2;

String serverSearchTerm(String value) {
  final trimmed = value.trim();
  return trimmed.runes.length >= serverSearchMinimumLength ? trimmed : '';
}

bool serverSearchIsTooShort(String value) {
  final length = value.trim().runes.length;
  return length > 0 && length < serverSearchMinimumLength;
}
