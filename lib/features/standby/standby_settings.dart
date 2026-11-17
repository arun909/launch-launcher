import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/clock/digital_clock.dart';

/// Colours the standby clock can take: plain white, then the clock widget's
/// gradients.
const standbyAccents = <(String, List<Color>)>[
  ('Moonlight', [Color(0xFFFFFFFF), Color(0xFFB8C6DB)]),
  ...clockGradients,
];

/// The standby screen's design.
enum StandbyStyle {
  /// The big gradient clock with its glow and glass media tile.
  glow('Glow'),

  /// A vintage hi-fi deck: VU meters, a spinning record, a 7-segment clock
  /// and a 10-band EQ.
  deck('Deck');

  const StandbyStyle(this.label);

  final String label;
}

/// How the standby clock (the landscape screen saver) looks.
@immutable
class StandbySettings {
  const StandbySettings({
    this.font = ClockFont.geometric,
    this.weight = 200,
    this.accent = 'Aurora',
    this.nightMode = true,
    this.seconds = true,
    this.alarm = true,
    this.media = true,
    this.matchArt = true,
    this.beatPulse = true,
    this.glow = true,
    this.artGlow = false,
    this.style = StandbyStyle.glow,
  });

  /// Which design. Each keeps its own options; the rest are shared.
  final StandbyStyle style;

  final ClockFont font;

  /// 100 (thin) to 900, kept within what [font] has.
  final int weight;

  /// Name of one of [standbyAccents].
  final String accent;

  /// Dim, red-only clock from 10 PM to 6 AM, easy on the eyes in a dark room.
  final bool nightMode;

  /// The seconds, small, beside the minutes.
  final bool seconds;

  /// The next alarm under the time.
  final bool alarm;

  /// What's playing, in a glass tile along the bottom, with its controls.
  final bool media;

  /// While a song is shown, the clock takes the main colours of its cover.
  final bool matchArt;

  /// The glow behind the clock pulses with the beat of what the phone
  /// plays (needs the audio permission).
  final bool beatPulse;

  /// The soft gradient glow over the whole screen behind the time. Off:
  /// black, with the gradient on the digits only.
  final bool glow;

  /// While a song is shown, a dim, heavily blurred copy of its cover fills
  /// the background. Off by default.
  final bool artGlow;

  int get fontWeight => weight.clamp(font.minWeight, font.maxWeight);

  List<Color> get colors => standbyAccents.firstWhere((a) => a.$1 == accent, orElse: () => standbyAccents.first).$2;

  /// Whether [t] falls in night hours.
  bool isNight(DateTime t) => nightMode && (t.hour >= 22 || t.hour < 6);

  StandbySettings copyWith({
    ClockFont? font,
    int? weight,
    String? accent,
    bool? nightMode,
    bool? seconds,
    bool? alarm,
    bool? media,
    bool? matchArt,
    bool? beatPulse,
    bool? glow,
    bool? artGlow,
    StandbyStyle? style,
  }) => StandbySettings(
    font: font ?? this.font,
    weight: weight ?? this.weight,
    accent: accent ?? this.accent,
    nightMode: nightMode ?? this.nightMode,
    seconds: seconds ?? this.seconds,
    alarm: alarm ?? this.alarm,
    media: media ?? this.media,
    matchArt: matchArt ?? this.matchArt,
    beatPulse: beatPulse ?? this.beatPulse,
    glow: glow ?? this.glow,
    artGlow: artGlow ?? this.artGlow,
    style: style ?? this.style,
  );

  Map<String, dynamic> toJson() => {
    'font': font.name,
    'weight': weight,
    'accent': accent,
    'night': nightMode,
    'seconds': seconds,
    'alarm': alarm,
    'media': media,
    'matchArt': matchArt,
    'beatPulse': beatPulse,
    'glow': glow,
    'artGlow': artGlow,
    'style': style.name,
  };

  factory StandbySettings.fromJson(Map<String, dynamic> json) {
    const d = StandbySettings();
    return StandbySettings(
      font: ClockFont.values.asNameMap()[json['font']] ?? d.font,
      weight: ((json['weight'] as num?)?.toInt() ?? d.weight).clamp(100, 900),
      accent: json['accent'] as String? ?? d.accent,
      nightMode: json['night'] as bool? ?? d.nightMode,
      seconds: json['seconds'] as bool? ?? d.seconds,
      alarm: json['alarm'] as bool? ?? d.alarm,
      media: json['media'] as bool? ?? d.media,
      matchArt: json['matchArt'] as bool? ?? d.matchArt,
      beatPulse: json['beatPulse'] as bool? ?? d.beatPulse,
      glow: json['glow'] as bool? ?? d.glow,
      artGlow: json['artGlow'] as bool? ?? d.artGlow,
      style: StandbyStyle.values.asNameMap()[json['style']] ?? d.style,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StandbySettings &&
      other.font == font &&
      other.weight == weight &&
      other.accent == accent &&
      other.nightMode == nightMode &&
      other.seconds == seconds &&
      other.alarm == alarm &&
      other.media == media &&
      other.matchArt == matchArt &&
      other.beatPulse == beatPulse &&
      other.glow == glow &&
      other.artGlow == artGlow &&
      other.style == style;

  @override
  int get hashCode =>
      Object.hash(font, weight, accent, nightMode, seconds, alarm, media, matchArt, beatPulse, glow, artGlow, style);
}

/// The saved [StandbySettings]. The clock runs in its own engine and reads
/// them afresh with [load] each time it's shown.
class StandbyController extends ChangeNotifier {
  StandbyController(this._prefs) : _settings = load(_prefs);

  static const _key = 'standby.settings';

  final SharedPreferences _prefs;
  StandbySettings _settings;

  StandbySettings get settings => _settings;

  static StandbySettings load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return const StandbySettings();
    try {
      return StandbySettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const StandbySettings();
    }
  }

  void update(StandbySettings next) {
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
    _prefs.setString(_key, jsonEncode(next.toJson()));
  }
}
