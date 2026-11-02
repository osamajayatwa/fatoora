import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'arabic_pdf_cases.dart';

Future<Map<String, TtfParser>> loadPdfSourceFonts() async => {
  for (final weight in ['Regular', 'Bold'])
    'Cairo-$weight': TtfParser(
      await rootBundle.load('assets/fonts/Cairo/Cairo-$weight.ttf'),
    ),
};

// Check serialized PDF widths AND the subset font outlines, not just layout.
int expectPdfFontMetrics(
  Uint8List bytes,
  Map<String, TtfParser> sources, {
  String context = '',
  Set<int> forbiddenUnshaped = const {},
}) {
  final text = latin1.decode(bytes);
  final objects = <int, String>{};
  for (final match in RegExp(r'(\d+) 0 obj\b').allMatches(text)) {
    objects[int.parse(match[1]!)] = text.substring(
      match.end,
      text.indexOf('endobj', match.end),
    );
  }
  Uint8List stream(String object) {
    final marker = RegExp(r'stream\r?\n').firstMatch(object)!;
    final length = int.parse(
      RegExp(r'/Length\s+(\d+)').firstMatch(object)![1]!,
    );
    final data = latin1.encode(
      object.substring(marker.end, marker.end + length),
    );
    return Uint8List.fromList(
      object.contains('/FlateDecode') ? zlib.decode(data) : data,
    );
  }

  int reference(String object, String pattern) =>
      int.parse(RegExp(pattern).firstMatch(object)![1]!);

  var checked = 0;
  for (final object in objects.values) {
    if (!RegExp(r'/Subtype\s*/Type0\b').hasMatch(object)) continue;
    final name = RegExp(r'/BaseFont\s*/([^\s/]+)').firstMatch(object)![1]!;
    final source = sources[name]!;
    final cmap = latin1.decode(
      stream(objects[reference(object, r'/ToUnicode\s+(\d+) 0 R')]!),
    );
    final widthsObject =
        objects[reference(object, r'/W\s*\[\s*0\s+(\d+) 0 R')]!;
    final widths = RegExp(
      r'-?\d+(?:\.\d+)?',
    ).allMatches(widthsObject).map((m) => double.parse(m[0]!)).toList();
    final subset = TtfParser(
      ByteData.sublistView(
        stream(objects[reference(object, r'/FontFile2\s+(\d+) 0 R')]!),
      ),
    );
    final aliases = {
      for (final letter in arabicLetterForms.entries)
        letter.value['isolated']!: letter.key,
    };
    for (final section in RegExp(
      r'beginbfchar([\s\S]*?)endbfchar',
    ).allMatches(cmap)) {
      for (final entry in RegExp(
        r'<([0-9A-F]+)>\s*<([0-9A-F]+)>',
      ).allMatches(section[1]!)) {
        final cid = int.parse(entry[1]!, radix: 16);
        final rune = int.parse(entry[2]!, radix: 16);
        if (rune == 0) continue;
        expect(
          forbiddenUnshaped,
          isNot(contains(rune)),
          reason: '$context contains an unshaped joining letter',
        );
        final glyph = source.charToGlyphIndexMap[aliases[rune] ?? rune];
        expect(glyph, isNotNull, reason: '$name U+${rune.toRadixString(16)}');
        final expected = source.glyphInfoMap[glyph]!;
        final actual = subset.glyphInfoMap[cid]!;
        final reason = '$context $name CID $cid / U+${rune.toRadixString(16)}';
        expect(
          widths[cid] / 1000,
          closeTo(expected.advanceWidth, .001),
          reason: reason,
        );
        expect(actual.advanceWidth, expected.advanceWidth, reason: reason);
        expect(actual.left, expected.left, reason: reason);
        expect(actual.top, expected.top, reason: reason);
        expect(actual.right, expected.right, reason: reason);
        expect(actual.bottom, expected.bottom, reason: reason);
        checked++;
      }
    }
  }
  expect(checked, greaterThan(0));
  return checked;
}
