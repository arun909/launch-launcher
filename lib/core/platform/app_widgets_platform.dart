import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A widget an installed app offers for the home screen, and the sizes it
/// asks for (in dp; see appWidgetItem for turning them into cells).
class AppWidgetProvider {
  const AppWidgetProvider({
    required this.provider,
    required this.packageName,
    required this.label,
    required this.appLabel,
    required this.minWidthDp,
    required this.minHeightDp,
    this.description,
    this.minResizeWidthDp = 0,
    this.minResizeHeightDp = 0,
    this.maxResizeWidthDp = 0,
    this.maxResizeHeightDp = 0,
    this.resizeHorizontal = false,
    this.resizeVertical = false,
    this.targetCellWidth = 0,
    this.targetCellHeight = 0,
    this.reconfigurable = false,
  });

  /// "package/class": what [AppWidgetsPlatform.addWidget] takes.
  final String provider;
  final String packageName;
  final String label;
  final String appLabel;
  final String? description;

  /// The size it starts at by default.
  final int minWidthDp;
  final int minHeightDp;

  /// The least and most it can be resized to; 0 if it doesn't say.
  final int minResizeWidthDp;
  final int minResizeHeightDp;
  final int maxResizeWidthDp;
  final int maxResizeHeightDp;

  /// Which ways it can be resized at all.
  final bool resizeHorizontal;
  final bool resizeVertical;

  /// The size in cells the app asks for (Android 12+); 0 if it doesn't say.
  final int targetCellWidth;
  final int targetCellHeight;

  /// Its settings screen can be reopened after it's added.
  final bool reconfigurable;

  factory AppWidgetProvider.fromMap(Map<dynamic, dynamic> map) {
    int dp(String key) => (map[key] as num?)?.toInt() ?? 0;
    return AppWidgetProvider(
      provider: map['provider'] as String,
      packageName: map['packageName'] as String,
      label: map['label'] as String? ?? '',
      appLabel: map['appLabel'] as String? ?? '',
      description: map['description'] as String?,
      minWidthDp: dp('minWidthDp'),
      minHeightDp: dp('minHeightDp'),
      minResizeWidthDp: dp('minResizeWidthDp'),
      minResizeHeightDp: dp('minResizeHeightDp'),
      maxResizeWidthDp: dp('maxResizeWidthDp'),
      maxResizeHeightDp: dp('maxResizeHeightDp'),
      resizeHorizontal: map['resizeHorizontal'] as bool? ?? false,
      resizeVertical: map['resizeVertical'] as bool? ?? false,
      targetCellWidth: dp('targetCellWidth'),
      targetCellHeight: dp('targetCellHeight'),
      reconfigurable: map['reconfigurable'] as bool? ?? false,
    );
  }
}

/// Dart side of the app-widget host. The Kotlin counterpart is
/// `android/app/src/main/kotlin/.../platform/AppWidgetsChannel.kt`; channel
/// names and method signatures here must match it.
class AppWidgetsPlatform {
  AppWidgetsPlatform() {
    _method.setMethodCallHandler(_onNativeCall);
  }

  static const _method = MethodChannel('com.arun.minimal_launcher/app_widgets');

  /// Ids of the shown app widgets that hold a list or grid (and so take
  /// vertical drags, to scroll; see AppWidgetView).
  final scrollable = ValueNotifier<Set<int>>(const {});

  /// Platform view that draws one app widget (see AppWidgetView).
  static const viewType = 'com.arun.minimal_launcher/app_widget';

  final _previews = <String, Future<Uint8List?>>{};

  /// Every widget installed apps offer, sorted by app and then widget name.
  Future<List<AppWidgetProvider>> getProviders() async {
    final list = await _method.invokeListMethod<Map<dynamic, dynamic>>('getProviders');
    return (list ?? const []).map(AppWidgetProvider.fromMap).toList()..sort((a, b) {
      final byApp = a.appLabel.toLowerCase().compareTo(b.appLabel.toLowerCase());
      return byApp != 0 ? byApp : a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
  }

  /// PNG preview of the widget as it will look at [size] (dp): its preview
  /// layout drawn at that size where it has one, else its preview image or
  /// icon. Loaded once per size.
  Future<Uint8List?> preview(String provider, Size size) => _previews.putIfAbsent(
    '$provider@${size.width.round()}x${size.height.round()}',
    () => _method
        .invokeMethod<Uint8List>('getPreview', {
          'provider': provider,
          'widthDp': size.width,
          'heightDp': size.height,
          'sizePx': 480,
        })
        .catchError((_) => null),
  );

  /// Binds [provider] to this launcher, telling it the [size] (dp) it will
  /// be shown at, asking the user's permission and opening the widget's
  /// setup screen if needed. Returns its Android id, or null if it wasn't
  /// added (cancelled, or the app is gone).
  Future<int?> addWidget(String provider, Size size) =>
      _method.invokeMethod<int>('addWidget', {'provider': provider, 'widthDp': size.width, 'heightDp': size.height});

  /// Reopens a widget's settings screen. False if it couldn't be opened.
  Future<bool> reconfigure(int appWidgetId) async =>
      await _method.invokeMethod<bool>('reconfigure', {'appWidgetId': appWidgetId}) ?? false;

  final _looks = <int, (double, double)>{};

  /// A shown app widget's corner radius in dp and how much it's scaled down
  /// (both applied natively; see AppWidgetView). Sent only when they change.
  void setLook(int appWidgetId, {required double radius, required double scale}) {
    if (_looks[appWidgetId] == (radius, scale)) return;
    _looks[appWidgetId] = (radius, scale);
    _method.invokeMethod('setLook', {'appWidgetId': appWidgetId, 'radius': radius, 'scale': scale});
  }

  /// Releases a removed widget's id.
  Future<void> deleteWidget(int appWidgetId) => _method.invokeMethod('deleteWidget', {'appWidgetId': appWidgetId});

  /// Releases every id of ours not in [appWidgetIds] (left over from widgets
  /// removed while the app wasn't running).
  Future<void> keepOnly(Iterable<int> appWidgetIds) =>
      _method.invokeMethod('keepOnly', {'appWidgetIds': appWidgetIds.toList()});

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onScrollable':
        final args = call.arguments as Map<dynamic, dynamic>;
        final id = args['appWidgetId'] as int;
        final ids = {...scrollable.value};
        (args['scrollable'] as bool) ? ids.add(id) : ids.remove(id);
        scrollable.value = ids;
    }
  }
}
