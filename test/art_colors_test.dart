import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/features/standby/art_colors.dart';
import 'package:minimal_launcher/features/standby/standby_settings.dart';

/// [n] pixels of each colour, as RGBA bytes.
Uint8List _pixels(Map<Color, int> counts) {
  final out = <int>[];
  counts.forEach((c, n) {
    for (var i = 0; i < n; i++) {
      out.addAll([(c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), 255]);
    }
  });
  return Uint8List.fromList(out);
}

double _hue(Color c) => HSVColor.fromColor(c).hue;

void main() {
  test('the strongest colour first, then a clearly different one', () {
    final colors = pickArtColors(
      _pixels({const Color(0xFFE53935): 500, const Color(0xFF1E88E5): 250, const Color(0xFF111111): 274}),
    )!;
    expect(_hue(colors[0]), closeTo(_hue(const Color(0xFFE53935)), 8));
    expect(_hue(colors[1]), closeTo(_hue(const Color(0xFF1E88E5)), 8));
  });

  test('both are bright enough to read on black', () {
    final colors = pickArtColors(_pixels({const Color(0xFF3A1D5C): 800, const Color(0xFF2B4A1A): 224}))!;
    for (final c in colors) {
      expect(HSVColor.fromColor(c).value, greaterThanOrEqualTo(0.8));
    }
  });

  test('one colour only: the second is a shifted shade of it', () {
    final colors = pickArtColors(_pixels({const Color(0xFF43A047): 1024}))!;
    final d = (_hue(colors[1]) - _hue(colors[0])).abs();
    expect(d, inInclusiveRange(25, 45));
  });

  test('a black-and-white cover gives none: the clock keeps its own colours', () {
    expect(
      pickArtColors(
        _pixels({const Color(0xFF000000): 400, const Color(0xFFFFFFFF): 400, const Color(0xFF808080): 224}),
      ),
      isNull,
    );
    expect(pickArtColors(Uint8List(0)), isNull);
  });

  test('the setting is saved, and on by default', () {
    expect(const StandbySettings().matchArt, isTrue);
    const off = StandbySettings(matchArt: false);
    expect(StandbySettings.fromJson(off.toJson()), off);
  });
}
