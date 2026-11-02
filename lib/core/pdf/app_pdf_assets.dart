import 'package:fatoora/core/constants/imageassests.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class AppPdfAssets {
  const AppPdfAssets({
    required this.regularFont,
    required this.boldFont,
    required this.logo,
  });

  final pw.Font regularFont;
  final pw.Font boldFont;
  final pw.MemoryImage? logo;

  static Future<AppPdfAssets>? _withoutLogo;
  static Future<AppPdfAssets>? _withLogo;

  static Future<AppPdfAssets> load({bool loadLogo = true}) {
    if (loadLogo) return _withLogo ??= _load(loadLogo: true);
    return _withoutLogo ??= _load(loadLogo: false);
  }

  static Future<AppPdfAssets> _load({required bool loadLogo}) async {
    final regular = _CairoPdfFont(
      await rootBundle.load('assets/fonts/Cairo/Cairo-Regular.ttf'),
    );
    final bold = _CairoPdfFont(
      await rootBundle.load('assets/fonts/Cairo/Cairo-Bold.ttf'),
    );

    pw.MemoryImage? logo;
    if (loadLogo) {
      try {
        final bytes = await rootBundle.load(ImageAssest.logo);
        logo = pw.MemoryImage(bytes.buffer.asUint8List());
      } catch (_) {
        logo = null;
      }
    }

    return AppPdfAssets(regularFont: regular, boldFont: bold, logo: logo);
  }

  pw.ThemeData get theme => pw.ThemeData.withFont(
    base: regularFont,
    bold: boldFont,
    fontFallback: [regularFont],
  );
}

class _CairoPdfFont extends pw.TtfFont {
  _CairoPdfFont(super.data);

  @override
  PdfFont buildFont(PdfDocument pdfDocument) {
    final font = _CairoEmbeddedFont(pdfDocument, data, protect: protect);
    final glyphs = font.font.charToGlyphIndexMap;

    // Cairo omits cmap entries for some isolated presentation forms. The
    // shaper still emits them, so map missing forms to their base glyphs.
    for (final alias in _isolatedArabicForms.entries) {
      final glyph = glyphs[alias.value];
      if (glyph != null && (glyphs[alias.key] ?? 0) == 0) {
        glyphs[alias.key] = glyph;
      }
    }
    // pdf 3.11.3 incorrectly aliases isolated alef maksura to dotted yeh.
    final alefMaksura = glyphs[0x0649];
    if (alefMaksura != null) glyphs[0xfeef] = alefMaksura;

    return font;
  }

  // Unicode isolated presentation form -> base letter.
  static const _isolatedArabicForms = <int, int>{
    0xfb50: 0x0671,
    0xfb56: 0x067e,
    0xfb66: 0x0679,
    0xfb6a: 0x06a4,
    0xfb7a: 0x0686,
    0xfb88: 0x0688,
    0xfb8a: 0x0698,
    0xfb8c: 0x0691,
    0xfb8e: 0x06a9,
    0xfb92: 0x06af,
    0xfb9e: 0x06ba,
    0xfba6: 0x06c1,
    0xfbaa: 0x06be,
    0xfbae: 0x06d2,
    0xfbb0: 0x06d3,
    0xfbfc: 0x06cc,
    0xfe80: 0x0621,
    0xfe81: 0x0622,
    0xfe83: 0x0623,
    0xfe85: 0x0624,
    0xfe87: 0x0625,
    0xfe89: 0x0626,
    0xfe8d: 0x0627,
    0xfe8f: 0x0628,
    0xfe93: 0x0629,
    0xfe95: 0x062a,
    0xfe99: 0x062b,
    0xfe9d: 0x062c,
    0xfea1: 0x062d,
    0xfea5: 0x062e,
    0xfea9: 0x062f,
    0xfeab: 0x0630,
    0xfead: 0x0631,
    0xfeaf: 0x0632,
    0xfeb1: 0x0633,
    0xfeb5: 0x0634,
    0xfeb9: 0x0635,
    0xfebd: 0x0636,
    0xfec1: 0x0637,
    0xfec5: 0x0638,
    0xfec9: 0x0639,
    0xfecd: 0x063a,
    0xfed1: 0x0641,
    0xfed5: 0x0642,
    0xfed9: 0x0643,
    0xfedd: 0x0644,
    0xfee1: 0x0645,
    0xfee5: 0x0646,
    0xfee9: 0x0647,
    0xfeed: 0x0648,
    0xfeef: 0x0649,
    0xfef1: 0x064a,
  };
}

class _CairoEmbeddedFont extends PdfTtfFont {
  _CairoEmbeddedFont(super.pdfDocument, super.bytes, {super.protect});

  final _encodedRuneByGlyph = <int, int>{};

  @override
  void putText(stream, String text) {
    // The PDF subsetter removes each source glyph after its first CID.
    // Give aliases the same CID so later aliases cannot pick another outline.
    final canonicalText = String.fromCharCodes(
      text.runes.map((rune) {
        final glyph = font.charToGlyphIndexMap[rune];
        if (glyph == null) return rune;
        return _encodedRuneByGlyph.putIfAbsent(glyph, () => rune);
      }),
    );
    super.putText(stream, canonicalText);
  }
}
