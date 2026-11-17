import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/platform/device_stats_platform.dart';

/// The weather now, as a clock shows it.
@immutable
class Weather {
  const Weather({required this.tempC, required this.code, required this.isDay, required this.at, this.place});

  factory Weather.fromJson(Map<String, dynamic> j) => Weather(
    tempC: (j['tempC'] as num).toDouble(),
    code: (j['code'] as num).toInt(),
    isDay: j['isDay'] as bool? ?? true,
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    place: j['place'] as String?,
  );

  final double tempC;

  /// WMO weather code, as Open-Meteo gives it.
  final int code;
  final bool isDay;

  /// When it was fetched.
  final DateTime at;

  /// Where it is for.
  final String? place;

  Map<String, dynamic> toJson() => {
    'tempC': tempC,
    'code': code,
    'isDay': isDay,
    'at': at.millisecondsSinceEpoch,
    'place': ?place,
  };

  /// "24°" (or in Fahrenheit).
  String temperature({bool fahrenheit = false}) => '${(fahrenheit ? tempC * 9 / 5 + 32 : tempC).round()}°';

  IconData get icon => weatherIcon(code, isDay: isDay);

  String get description => weatherDescription(code);
}

/// A standard icon for a WMO weather code.
IconData weatherIcon(int code, {bool isDay = true}) => switch (code) {
  0 || 1 => isDay ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
  2 => isDay ? Icons.wb_cloudy_outlined : Icons.nights_stay_outlined,
  3 => Icons.cloud_outlined,
  45 || 48 => Icons.foggy,
  >= 51 && <= 57 => Icons.grain_rounded,
  >= 61 && <= 67 || >= 80 && <= 82 => Icons.umbrella_outlined,
  >= 71 && <= 77 || 85 || 86 => Icons.ac_unit_rounded,
  >= 95 => Icons.thunderstorm_outlined,
  _ => Icons.cloud_outlined,
};

String weatherDescription(int code) => switch (code) {
  0 => 'Clear',
  1 => 'Mostly clear',
  2 => 'Partly cloudy',
  3 => 'Cloudy',
  45 || 48 => 'Fog',
  >= 51 && <= 57 => 'Drizzle',
  >= 61 && <= 67 || >= 80 && <= 82 => 'Rain',
  >= 71 && <= 77 || 85 || 86 => 'Snow',
  >= 95 => 'Thunderstorm',
  _ => 'Cloudy',
};

/// A town picked for the weather, instead of the phone's location.
@immutable
class WeatherCity {
  const WeatherCity({required this.name, required this.lat, required this.lon, this.detail});

  factory WeatherCity.fromJson(Map<String, dynamic> j) => WeatherCity(
    name: j['name'] as String,
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    detail: j['detail'] as String?,
  );

  final String name;
  final double lat;
  final double lon;

  /// Region and country, to tell same-named towns apart.
  final String? detail;

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lon': lon, 'detail': ?detail};
}

/// Why there's no weather.
enum WeatherProblem { noLocation, offline }

/// The weather for every clock that shows it, from Open-Meteo (free, no
/// account or key): for the phone's approximate location, or a [city]
/// picked instead.
///
/// Fetched only while such a clock is on screen ([attach] / [detach]) and
/// the launcher is in front, at most every 30 minutes; the last one is
/// kept, so a clock shows it at once.
class WeatherController extends ChangeNotifier with WidgetsBindingObserver {
  WeatherController(this._prefs, this._platform) {
    WidgetsBinding.instance.addObserver(this);
    _weather = _read(_kNow, Weather.fromJson);
    _city = _read(_kCity, WeatherCity.fromJson);
  }

  final SharedPreferences _prefs;
  final DeviceStatsPlatform _platform;

  static const _kNow = 'weather.now', _kCity = 'weather.city';
  static const _every = Duration(minutes: 30);

  int _users = 0;
  bool _foreground = true;
  bool _disposed = false;
  bool _loading = false;
  Timer? _timer;

  Weather? get weather => _weather;
  Weather? _weather;

  /// The town picked; null: the phone's location.
  WeatherCity? get city => _city;
  WeatherCity? _city;

  WeatherProblem? get problem => _problem;
  WeatherProblem? _problem;

  T? _read<T>(String key, T Function(Map<String, dynamic>) from) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return from(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void attach() {
    _users++;
    _update();
  }

  void detach() {
    _users--;
    _update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final front = state == AppLifecycleState.resumed;
    if (front == _foreground) return;
    _foreground = front;
    _update();
  }

  void _update() {
    if (_users > 0 && _foreground) {
      final w = _weather;
      if (w == null || DateTime.now().difference(w.at) >= _every || _problem != null) refresh();
      _timer ??= Timer.periodic(_every, (_) => refresh());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Whether approximate location is allowed.
  Future<bool> hasLocation() => _platform.hasLocation().catchError((Object _) => false);

  Future<void> requestLocation() => _platform.requestLocation();

  /// The weather for the phone's location from now on.
  Future<void> useLocation() async {
    _city = null;
    await _prefs.remove(_kCity);
    notifyListeners();
    await refresh();
  }

  /// The weather for [city] from now on.
  Future<void> useCity(WeatherCity city) async {
    _city = city;
    await _prefs.setString(_kCity, jsonEncode(city.toJson()));
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final city = _city;
      final (double, double, String?) point;
      if (city != null) {
        point = (city.lat, city.lon, city.name);
      } else {
        final here = await _platform.location().catchError((Object _) => null);
        if (here == null) return _fail(WeatherProblem.noLocation);
        point = (here.lat, here.lon, here.place);
      }
      final (lat, lon, place) = point;
      final j = await _getJson(
        Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': lat.toStringAsFixed(3),
          'longitude': lon.toStringAsFixed(3),
          'current': 'temperature_2m,weather_code,is_day',
          'timezone': 'auto',
        }),
      );
      final now = j?['current'] as Map<String, dynamic>?;
      if (now == null) return _fail(WeatherProblem.offline);
      final w = Weather(
        tempC: (now['temperature_2m'] as num).toDouble(),
        code: (now['weather_code'] as num).toInt(),
        isDay: (now['is_day'] as num?) != 0,
        at: DateTime.now(),
        place: place,
      );
      if (_disposed) return;
      _weather = w;
      _problem = null;
      await _prefs.setString(_kNow, jsonEncode(w.toJson()));
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  void _fail(WeatherProblem p) {
    if (_disposed || _problem == p) return;
    _problem = p;
    notifyListeners();
  }

  /// Towns matching [query], best first.
  Future<List<WeatherCity>> searchCities(String query) async {
    if (query.trim().length < 2) return const [];
    final j = await _getJson(
      Uri.https('geocoding-api.open-meteo.com', '/v1/search', {'name': query.trim(), 'count': '8'}),
    );
    return [
      for (final r in (j?['results'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
        WeatherCity(
          name: r['name'] as String,
          lat: (r['latitude'] as num).toDouble(),
          lon: (r['longitude'] as num).toDouble(),
          detail: [r['admin1'], r['country']].whereType<String>().join(', '),
        ),
    ];
  }

  static Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }
}
