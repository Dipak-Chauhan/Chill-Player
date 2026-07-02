import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_player/theme/color_provider.dart';

/// Renders a solid-colour PNG to feed the extractor.
Future<Uint8List> solidPng(Color color, {int size = 16}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FastColorExtractor', () {
    test('picks a reddish dominant from a red image', () async {
      final colors = await FastColorExtractor.extract(await solidPng(const Color(0xFFCC3333)));
      expect(colors.dominant.r, greaterThan(colors.dominant.g));
      expect(colors.dominant.r, greaterThan(colors.dominant.b));
    });

    test('picks a bluish dominant from a blue image', () async {
      final colors = await FastColorExtractor.extract(await solidPng(const Color(0xFF3333CC)));
      expect(colors.dominant.b, greaterThan(colors.dominant.r));
      expect(colors.dominant.b, greaterThan(colors.dominant.g));
    });

    test('returns a neutral color for a grey image', () async {
      final colors = await FastColorExtractor.extract(await solidPng(const Color(0xFF808080)));
      // Grey has no vibrant bucket, so it falls back to the average -> equal channels.
      expect((colors.dominant.r - colors.dominant.g).abs(), lessThan(0.1));
      expect((colors.dominant.g - colors.dominant.b).abs(), lessThan(0.1));
    });

    test('empty bytes yield the default colors', () async {
      final colors = await FastColorExtractor.extract(Uint8List(0));
      expect(colors.dominant, ExtractedColors.defaultColors.dominant);
    });
  });
}
