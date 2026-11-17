import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the instant-search widget hands to an app.
enum InstantKind {
  /// A search: typed, spoken or a scanned text.
  text,

  /// A link, UPI payment, phone number… (anything with a scheme).
  link,

  /// A picked image.
  image,
}

/// One app that can take a search, link or image (from
/// [InstantPlatform.targets]); passed back to [InstantPlatform.open].
@immutable
class InstantTarget {
  const InstantTarget(this._raw);

  factory InstantTarget.fromMap(Map<dynamic, dynamic> map) => InstantTarget(Map<String, Object?>.from(map));

  final Map<String, Object?> _raw;

  String get packageName => _raw['package'] as String;
  String get label => _raw['label'] as String;
}

/// A place hold-to-search can search (Google, ChatGPT, Play Store…).
@immutable
class HoldSearchPlace {
  const HoldSearchPlace({required this.id, required this.label, required this.installed, required this.shown, this.icon});

  factory HoldSearchPlace.fromMap(Map<dynamic, dynamic> m) => HoldSearchPlace(
    id: m['id'] as String,
    label: m['label'] as String,
    installed: m['installed'] as bool? ?? false,
    shown: m['shown'] as bool? ?? false,
    icon: m['icon'] as Uint8List?,
  );

  final String id;
  final String label;

  /// Its app is on the phone (else it's searched on the web only).
  final bool installed;

  /// In the bar.
  final bool shown;
  final Uint8List? icon;

  HoldSearchPlace copyWith({bool? shown}) =>
      HoldSearchPlace(id: id, label: label, installed: installed, shown: shown ?? this.shown, icon: icon);
}

/// Why a scan / voice input didn't give anything.
class InstantError implements Exception {
  const InstantError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Dart side of `InstantChannel.kt` (channel `com.arun.minimal_launcher/instant`);
/// keep both in sync.
class InstantPlatform {
  static const _method = MethodChannel('com.arun.minimal_launcher/instant');

  /// Apps that can take [kind], best first. For [InstantKind.link], those
  /// that open [data]; empty if none do.
  Future<List<InstantTarget>> targets(InstantKind kind, {String? data}) async {
    final list = await _method.invokeListMethod<Map<dynamic, dynamic>>('targets', {'kind': kind.name, 'data': data});
    return (list ?? const []).map(InstantTarget.fromMap).toList();
  }

  /// Hands [text] (a search or link) or [file] (an image) to [target]; with
  /// neither, just opens the app. False if it couldn't be opened.
  Future<bool> open(InstantTarget target, {String? text, String? file}) async =>
      await _method.invokeMethod<bool>('open', {'target': target._raw, 'text': text, 'file': file}) ?? false;

  /// Android's share sheet, for every other app.
  Future<bool> more(InstantKind kind, {String? text, String? file}) async =>
      await _method.invokeMethod<bool>('more', {'kind': kind.name, 'text': text, 'file': file}) ?? false;

  /// Scans a QR code or barcode with the phone's (Google's) scanner: its
  /// text, or null if cancelled.
  Future<String?> scan() => _call('scan');

  /// Voice input: what was said, or null if cancelled.
  Future<String?> listen() => _call('listen');

  /// The photo picker: a private copy's path, or null if cancelled.
  Future<String?> pickImage() => _call('pickImage');

  /// The live viewfinder: one tap takes a photo; its private file's path,
  /// or null if cancelled.
  Future<String?> capture() => _call('capture');

  Future<bool> openCamera() async => await _method.invokeMethod<bool>('openCamera') ?? false;

  Future<bool> openRecorder() async => await _method.invokeMethod<bool>('openRecorder') ?? false;

  /// Chrome straight into [action]: `incognito` (a new Incognito tab),
  /// `search` (its search box) or `url` ([url]). False if Chrome isn't
  /// installed or wouldn't open.
  Future<bool> chrome(String action, {String? url}) async =>
      await _method.invokeMethod<bool>('chrome', {'action': action, 'url': url}) ?? false;

  /// Whether the full-screen button over browsers (an accessibility
  /// service) is on.
  Future<bool> browserButton() async => await _method.invokeMethod<bool>('browserButton') ?? false;

  /// Turns the full-screen button on or off; false if the launcher can't
  /// itself, and it must be done in Android's accessibility settings
  /// ([openBrowserButtonSettings]).
  Future<bool> setBrowserButton(bool on) async =>
      await _method.invokeMethod<bool>('setBrowserButton', {'on': on}) ?? false;

  /// Whether hold-to-search (touch and hold the bottom centre of the
  /// screen in any app) is on. Same accessibility service as the button.
  Future<bool> holdSearch() async => await _method.invokeMethod<bool>('holdSearch') ?? false;

  /// Turns hold-to-search on or off; false if Android's accessibility
  /// settings must be opened ([openBrowserButtonSettings]).
  Future<bool> setHoldSearch(bool on) async => await _method.invokeMethod<bool>('setHoldSearch', {'on': on}) ?? false;

  /// Every place hold-to-search can search, the bar's ones first in the
  /// bar's order.
  Future<List<HoldSearchPlace>> holdSearchPlaces() async {
    final list = await _method.invokeListMethod<Map<dynamic, dynamic>>('holdSearchPlaces');
    return (list ?? const []).map(HoldSearchPlace.fromMap).toList();
  }

  /// The places in hold-to-search's bar, in order.
  Future<void> setHoldSearchPlaces(List<String> ids) => _method.invokeMethod('setHoldSearchPlaces', {'ids': ids});

  Future<bool> openBrowserButtonSettings() async =>
      await _method.invokeMethod<bool>('browserButtonSettings') ?? false;

  Future<String?> _call(String method) async {
    try {
      return await _method.invokeMethod<String>(method);
    } on PlatformException catch (e) {
      throw InstantError(switch (e.code) {
        'SCANNER_DOWNLOADING' => 'The scanner is being set up. Try again in a moment.',
        'UNAVAILABLE' => 'No app on this phone can do that',
        'BUSY' => 'Already open',
        'CAMERA_DENIED' => 'Allow the camera in the launcher\'s app settings to take photos',
        _ => e.message ?? 'Something went wrong',
      });
    }
  }
}
