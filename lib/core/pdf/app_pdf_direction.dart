import 'package:pdf/widgets.dart' as pw;

class AppPdfDirection {
  const AppPdfDirection._();

  static final RegExp _arabicPattern = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
  );
  static final RegExp _latinOrDigitPattern = RegExp(r'[A-Za-z0-9]');

  static bool hasArabic(String value) => _arabicPattern.hasMatch(value);

  static bool hasLatinOrDigit(String value) =>
      _latinOrDigitPattern.hasMatch(value);

  static bool isLtrOnly(String value) =>
      value.trim().isNotEmpty && !hasArabic(value) && hasLatinOrDigit(value);

  static pw.TextDirection directionOf(
    String value, {
    pw.TextDirection fallback = pw.TextDirection.ltr,
  }) {
    if (hasArabic(value)) return pw.TextDirection.rtl;
    if (hasLatinOrDigit(value)) return pw.TextDirection.ltr;
    return fallback;
  }

  static pw.TextAlign alignOf(
    String value, {
    pw.TextDirection fallback = pw.TextDirection.ltr,
  }) {
    return directionOf(value, fallback: fallback) == pw.TextDirection.rtl
        ? pw.TextAlign.right
        : pw.TextAlign.left;
  }

  static pw.Widget text(
    String value, {
    pw.TextStyle? style,
    pw.TextAlign? textAlign,
    int? maxLines,
    pw.TextDirection fallbackDirection = pw.TextDirection.ltr,
    bool softWrap = true,
  }) {
    final safeValue = value.trim().isEmpty ? '-' : value.trim();
    final direction = directionOf(safeValue, fallback: fallbackDirection);
    return pw.Directionality(
      textDirection: direction,
      child: pw.Text(
        safeValue,
        style: style,
        textDirection: direction,
        textAlign: textAlign ?? alignOf(safeValue, fallback: fallbackDirection),
        maxLines: maxLines,
        softWrap: softWrap,
      ),
    );
  }
}
