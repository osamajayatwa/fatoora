import 'package:fatoora/core/constants/imageassests.dart';
import 'package:flutter/services.dart';
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
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo/Cairo-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
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
