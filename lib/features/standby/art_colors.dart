import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The two main colours of a song's cover, made to read well as the standby
/// clock's gradient on black. Null when the cover is (nearly) colourless, so
/// the clock keeps its own colours.
Future<List<Color>?> artColors(Uint8List encoded) async {
  try {
    final codec = await ui.instantiateImageCodec(encoded, targetWidth: _side, targetHeight: _side);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    return data == null ? null : pickArtColors(data.buffer.asUint8List());
  } on Exception {
    return null;
  }
}

const _side = 32;
const _buckets = 24; // 15° of hue each

/// [rgba]: pixels, 4 bytes each. Vivid pixels count most; greys, near-black
/// and near-white not at all. The strongest hue first, then the strongest one
/// at least 40° away (or a shifted shade of the first if there's none).
List<Color>? pickArtColors(Uint8List rgba) {
  final weight = List<double>.filled(_buckets, 0);
  final hue = List<double>.filled(_buckets, 0); // weighted sums, as unit vectors
  final hueY = List<double>.filled(_buckets, 0);
  final sat = List<double>.filled(_buckets, 0);
  final val = List<double>.filled(_buckets, 0);
  var pixels = 0;
  var vivid = 0;

  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    pixels++;
    final c = HSVColor.fromColor(Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]));
    if (c.saturation < 0.2 || c.value < 0.18) continue;
    // Vivid and bright counts most; washed-out highlights count less.
    final w = c.saturation * c.saturation * c.value;
    final b = (c.hue / 360 * _buckets).floor() % _buckets;
    vivid++;
    final rad = c.hue * math.pi / 180;
    weight[b] += w;
    hue[b] += w * math.cos(rad);
    hueY[b] += w * math.sin(rad);
    sat[b] += w * c.saturation;
    val[b] += w * c.value;
  }
  // Under 4% of the cover is colourful: it's a grey/black-and-white one.
  if (pixels == 0 || vivid < pixels * 0.04) return null;

  // Neighbouring buckets together, so one hue split over two isn't missed.
  double around(int b) => weight[b] + 0.5 * (weight[(b + 1) % _buckets] + weight[(b - 1 + _buckets) % _buckets]);
  final order = [
    for (var b = 0; b < _buckets; b++)
      if (weight[b] > 0) b,
  ]..sort((a, b) => around(b).compareTo(around(a)));

  HSVColor colorOf(int b) {
    final w = weight[b];
    var h = math.atan2(hueY[b], hue[b]) * 180 / math.pi;
    if (h < 0) h += 360;
    return HSVColor.fromAHSV(1, h, sat[b] / w, val[b] / w);
  }

  if (order.isEmpty) return null;
  final first = order.first;
  final a = colorOf(first);
  int? second;
  for (final b in order.skip(1)) {
    if (weight[b] < weight[first] * 0.08) break;
    if (_hueDistance(colorOf(b).hue, a.hue) >= 40) {
      second = b;
      break;
    }
  }
  final b = second != null ? colorOf(second) : a.withHue((a.hue + 35) % 360);
  return [_legible(a), _legible(b)];
}

/// Bright and saturated enough to glow on black, never neon-harsh.
Color _legible(HSVColor c) =>
    c.withSaturation(c.saturation.clamp(0.45, 0.85)).withValue(c.value.clamp(0.82, 1.0)).toColor();

double _hueDistance(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}
