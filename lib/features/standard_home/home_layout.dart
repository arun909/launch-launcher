import 'dart:convert';
import 'dart:math' as math;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// One thing on a standard-mode home page: a single app, a container, or a
/// widget.
///
/// Items are kept in one ordered list; pages are derived from it by
/// [paginate], so there are never gaps to manage or positions to repair.
@immutable
sealed class HomeItem {
  const HomeItem();

  /// Unique within the layout; used for drag and drop and widget keys.
  String get key;

  /// Size in grid cells.
  int get cols;
  int get rows;

  Map<String, dynamic> toJson();

  static HomeItem fromJson(Map<String, dynamic> json) => switch (json['type']) {
    'container' => AppContainer.fromJson(json),
    'widget' => WidgetItem.fromJson(json),
    _ => AppItem(json['app'] as String),
  };
}

class AppItem extends HomeItem {
  const AppItem(this.appId);

  final String appId;

  @override
  String get key => 'app:$appId';

  @override
  int get cols => 1;

  @override
  int get rows => 1;

  @override
  Map<String, dynamic> toJson() => {'type': 'app', 'app': appId};

  @override
  bool operator ==(Object other) => other is AppItem && other.appId == appId;

  @override
  int get hashCode => appId.hashCode;
}

/// A folder's outline on the home screen (see FolderTile). Containers, and
/// a folder once opened, are always rounded rectangles.
enum FolderShape {
  /// The usual rounded square; its corners follow [AppContainer.cornerRadius].
  rounded,

  /// A circle, its apps evenly round a ring inside.
  circle,

  /// A circle with a soft, wavy edge, a petal for each app round its ring.
  flower,

  /// A rounded triangle, point up, its apps along its sides, one in each
  /// corner and the rest evenly between: for 3, 6, 9… apps.
  triangle,
}

/// A group's background (see AppContainerTile.decoration).
enum GroupStyle {
  /// A light, see-through white tint (the default).
  light,

  /// A darker, smoky see-through tint.
  dark,

  /// Frosted glass: blurs what's behind it.
  glass,

  /// A see-through tint of [AppContainer.color].
  color,

  /// A solid Material 3 dark surface: opaque, borderless, toned rather
  /// than tinted. (Stored as 'material', its name before the light one.)
  material,

  /// A solid Material 3 light surface, with dark content on it (see
  /// [isLightSurface] and PanelInk).
  materialLight;

  /// Its content is drawn dark (its surface is light).
  bool get isLightSurface => this == materialLight;

  /// The colour text and glyphs on it are drawn in.
  Color get ink => isLightSurface ? const Color(0xFF1B1C20) : const Color(0xFFFFFFFF);
}

/// A group of apps. Its size decides how it looks:
/// - 1 × 1: a folder, an app-icon-sized tile with a mini grid of its apps;
/// - bigger: a container, a rounded panel showing as many of its apps as fit
///   at normal icon size (the last spot a small cluster of the rest, if any).
///
/// Resizing one with its handles turns a folder into a container and back.
class AppContainer extends HomeItem {
  const AppContainer({
    required this.id,
    required this.name,
    required this.appIds,
    this.cols = 2,
    this.rows = 2,
    this.cornerRadius = defaultCornerRadius,
    this.style = GroupStyle.light,
    this.color = defaultColor,
    this.folderShape = FolderShape.rounded,
  });

  static const defaultColor = 0xFF5B8DEF;

  /// Up to the widest grid (see HomeGrid).
  static const maxSpan = 6;
  static const defaultCornerRadius = 28.0;
  static const maxCornerRadius = 64.0;

  final String id;
  final String name;
  final List<String> appIds;

  @override
  final int cols;

  @override
  final int rows;

  /// 0 (square) to [maxCornerRadius]. A folder, being icon-sized, scales it
  /// down: [maxCornerRadius] makes it a circle (see [radiusAt]).
  final double cornerRadius;

  final GroupStyle style;

  /// ARGB of the tint when [style] is [GroupStyle.color]; kept otherwise, so
  /// switching back brings the same colour.
  final int color;

  /// Its outline while it's a folder (1 × 1); kept as a container, so it
  /// comes back if shrunk to a folder again.
  final FolderShape folderShape;

  bool get isFolder => cols == 1 && rows == 1;

  /// At least one app in every row and column, so none is left empty: too
  /// wide → as wide as it has apps; then too tall → only the rows its apps
  /// reach (the last may be partly filled, e.g. 5 apps in 2 × 3 or 3 × 2).
  /// More apps than cells is fine: the last cell shows the rest.
  AppContainer fitted() {
    final n = math.max(1, appIds.length);
    final c = math.min(cols, n);
    final r = math.min(rows, rowsFilled(n, c));
    return c == cols && r == rows ? this : copyWith(cols: c, rows: r);
  }

  /// Rows that [apps] apps reach, filled row by row [cols] wide.
  static int rowsFilled(int apps, int cols) => math.max(1, (apps + cols - 1) ~/ cols);

  /// Corner radius for a panel of [size]: as set for a container; scaled to
  /// the same roundness for a folder's icon-sized tile.
  double radiusAt(double size) => isFolder ? cornerRadius / maxCornerRadius * size / 2 : cornerRadius;

  @override
  String get key => 'container:$id';

  AppContainer copyWith({
    String? name,
    List<String>? appIds,
    int? cols,
    int? rows,
    double? cornerRadius,
    GroupStyle? style,
    int? color,
    FolderShape? folderShape,
  }) => AppContainer(
    id: id,
    name: name ?? this.name,
    appIds: appIds ?? this.appIds,
    cols: (cols ?? this.cols).clamp(1, maxSpan),
    rows: (rows ?? this.rows).clamp(1, maxSpan),
    cornerRadius: (cornerRadius ?? this.cornerRadius).clamp(0.0, maxCornerRadius),
    style: style ?? this.style,
    color: color ?? this.color,
    folderShape: folderShape ?? this.folderShape,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'container',
    'id': id,
    'name': name,
    'apps': appIds,
    'cols': cols,
    'rows': rows,
    'radius': cornerRadius,
    'style': style.name,
    'color': color,
    'shape': folderShape.name,
  };

  factory AppContainer.fromJson(Map<String, dynamic> json) {
    // Older layouts stored folders as a flag; a folder is now just 1 × 1.
    final folder = json['folder'] as bool? ?? false;
    return AppContainer(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      appIds: List<String>.from(json['apps'] as List? ?? const []),
      cols: folder ? 1 : ((json['cols'] as num?)?.toInt() ?? 2).clamp(1, maxSpan),
      rows: folder ? 1 : ((json['rows'] as num?)?.toInt() ?? 2).clamp(1, maxSpan),
      cornerRadius: ((json['radius'] as num?)?.toDouble() ?? defaultCornerRadius).clamp(0.0, maxCornerRadius),
      style: GroupStyle.values.asNameMap()[json['style']] ?? GroupStyle.light,
      color: (json['color'] as num?)?.toInt() ?? defaultColor,
      folderShape: FolderShape.values.asNameMap()[json['shape']] ?? FolderShape.rounded,
    );
  }
}

/// A home-screen widget: one an app provides (an Android app widget, drawn
/// by Android; see AppWidgetView), or one of the launcher's own
/// ([launcherKind]; see LauncherWidgets).
///
/// Its span stays within [minCols]–[maxCols] × [minRows]–[maxRows]: the
/// least it needs to look right, and the most it may grow (equal when it
/// can't be resized that way).
///
/// An app widget also keeps the sizes its app asked for, in dp
/// ([minWidthDp] etc.), so those cell limits can be worked out again for
/// other cell sizes (another grid; see HomeWidgetView.fitTo).
///
/// It holds no apps, so syncing with installed apps leaves it alone.
class WidgetItem extends HomeItem {
  const WidgetItem({
    required this.id,
    this.appWidgetId,
    this.provider,
    this.launcherKind,
    this.cols = 2,
    this.rows = 2,
    this.minCols = 1,
    this.minRows = 1,
    this.maxCols = maxSpan,
    this.maxRows = maxSpan,
    this.minWidthDp = 0,
    this.minHeightDp = 0,
    this.maxWidthDp = 0,
    this.maxHeightDp = 0,
    this.reconfigurable = false,
    this.settings = const {},
  });

  /// The most a widget can span either way.
  static const maxSpan = AppContainer.maxSpan;

  final String id;

  /// Android's id for an app widget bound to this launcher; null for a
  /// launcher widget.
  final int? appWidgetId;

  /// The app widget's provider, as "package/class".
  final String? provider;

  /// Which launcher widget (LauncherWidgetKind's name); null for an app widget.
  final String? launcherKind;

  @override
  final int cols;

  @override
  final int rows;

  final int minCols;
  final int minRows;
  final int maxCols;
  final int maxRows;

  /// The least size the app widget can lay itself out in, and the most it
  /// may grow to (0: no limit), in dp. Equal least and most: a fixed size.
  /// All 0 for a launcher widget (its cell limits are its own).
  final double minWidthDp;
  final double minHeightDp;
  final double maxWidthDp;
  final double maxHeightDp;

  /// The app widget has a settings screen that can be reopened.
  final bool reconfigurable;

  /// A launcher widget's own options (its look), as its kind reads them;
  /// each instance has its own. Empty: the kind's defaults.
  final Map<String, dynamic> settings;

  bool get isAppWidget => appWidgetId != null;

  bool get resizable => minCols < maxCols || minRows < maxRows;

  String? get providerPackage => provider?.split('/').first;

  @override
  String get key => 'widget:$id';

  /// With a new span or new limits; the span is kept within the limits.
  WidgetItem copyWith({
    int? cols,
    int? rows,
    int? minCols,
    int? minRows,
    int? maxCols,
    int? maxRows,
    int? appWidgetId,
    Map<String, dynamic>? settings,
  }) {
    final loC = (minCols ?? this.minCols).clamp(1, maxSpan), loR = (minRows ?? this.minRows).clamp(1, maxSpan);
    final hiC = math.max(loC, (maxCols ?? this.maxCols).clamp(1, maxSpan));
    final hiR = math.max(loR, (maxRows ?? this.maxRows).clamp(1, maxSpan));
    return WidgetItem(
      id: id,
      appWidgetId: appWidgetId ?? this.appWidgetId,
      provider: provider,
      launcherKind: launcherKind,
      cols: (cols ?? this.cols).clamp(loC, hiC),
      rows: (rows ?? this.rows).clamp(loR, hiR),
      minCols: loC,
      minRows: loR,
      maxCols: hiC,
      maxRows: hiR,
      minWidthDp: minWidthDp,
      minHeightDp: minHeightDp,
      maxWidthDp: maxWidthDp,
      maxHeightDp: maxHeightDp,
      reconfigurable: reconfigurable,
      settings: settings ?? this.settings,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'widget',
    'id': id,
    'appWidgetId': ?appWidgetId,
    'provider': ?provider,
    'kind': ?launcherKind,
    'cols': cols,
    'rows': rows,
    'minCols': minCols,
    'minRows': minRows,
    'maxCols': maxCols,
    'maxRows': maxRows,
    if (minWidthDp > 0) 'minW': minWidthDp,
    if (minHeightDp > 0) 'minH': minHeightDp,
    if (maxWidthDp > 0) 'maxW': maxWidthDp,
    if (maxHeightDp > 0) 'maxH': maxHeightDp,
    if (reconfigurable) 'reconfigurable': true,
    if (settings.isNotEmpty) 'settings': settings,
  };

  factory WidgetItem.fromJson(Map<String, dynamic> json) {
    int span(String key, int fallback) => ((json[key] as num?)?.toInt() ?? fallback).clamp(1, maxSpan);
    double dp(String key) => (json[key] as num?)?.toDouble() ?? 0;
    final minCols = span('minCols', 1), minRows = span('minRows', 1);
    final maxCols = math.max(minCols, span('maxCols', maxSpan)), maxRows = math.max(minRows, span('maxRows', maxSpan));
    return WidgetItem(
      id: json['id'] as String,
      appWidgetId: (json['appWidgetId'] as num?)?.toInt(),
      provider: json['provider'] as String?,
      launcherKind: json['kind'] as String?,
      cols: span('cols', 2).clamp(minCols, maxCols),
      rows: span('rows', 2).clamp(minRows, maxRows),
      minCols: minCols,
      minRows: minRows,
      maxCols: maxCols,
      maxRows: maxRows,
      minWidthDp: dp('minW'),
      minHeightDp: dp('minH'),
      maxWidthDp: dp('maxW'),
      maxHeightDp: dp('maxH'),
      reconfigurable: json['reconfigurable'] as bool? ?? false,
      settings: (json['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetItem &&
      other.id == id &&
      other.appWidgetId == appWidgetId &&
      other.provider == provider &&
      other.launcherKind == launcherKind &&
      other.cols == cols &&
      other.rows == rows &&
      other.minCols == minCols &&
      other.minRows == minRows &&
      other.maxCols == maxCols &&
      other.maxRows == maxRows &&
      other.minWidthDp == minWidthDp &&
      other.minHeightDp == minHeightDp &&
      other.maxWidthDp == maxWidthDp &&
      other.maxHeightDp == maxHeightDp &&
      other.reconfigurable == reconfigurable &&
      mapEquals(other.settings, settings);

  @override
  int get hashCode => Object.hash(
    id,
    appWidgetId,
    provider,
    launcherKind,
    cols,
    rows,
    minCols,
    minRows,
    maxCols,
    maxRows,
    minWidthDp,
    minHeightDp,
    maxWidthDp,
    maxHeightDp,
    reconfigurable,
    Object.hashAllUnordered(settings.keys),
  );
}

String encodeLayout(List<HomeItem> items) => jsonEncode([for (final i in items) i.toJson()]);

/// Parses [encodeLayout] output; anything unreadable gives an empty layout
/// (which [syncWithInstalled] then fills with every app again).
List<HomeItem> decodeLayout(String? raw) {
  if (raw == null) return const [];
  try {
    return [for (final j in jsonDecode(raw) as List) HomeItem.fromJson(Map<String, dynamic>.from(j as Map))];
  } catch (_) {
    return const [];
  }
}

/// Every app id in [items], including those inside containers.
Iterable<String> allAppIds(List<HomeItem> items) sync* {
  for (final item in items) {
    switch (item) {
      case AppItem(:final appId):
        yield appId;
      case AppContainer(:final appIds):
        yield* appIds;
      case WidgetItem():
        break;
    }
  }
}

/// Makes [items] hold every id in [installed] exactly once: drops apps that
/// are no longer installed (and containers left empty), and appends new ones
/// at the end in [installed] order. Widgets are kept as they are. Returns
/// [items] itself if nothing changed.
List<HomeItem> syncWithInstalled(List<HomeItem> items, List<String> installed) {
  final installedSet = installed.toSet();
  final seen = <String>{};
  var changed = false;
  final result = <HomeItem>[];
  for (final item in items) {
    switch (item) {
      case AppItem(:final appId):
        if (installedSet.contains(appId) && seen.add(appId)) {
          result.add(item);
        } else {
          changed = true;
        }
      case AppContainer(:final appIds):
        final kept = [
          for (final id in appIds)
            if (installedSet.contains(id) && seen.add(id)) id,
        ];
        if (kept.length != appIds.length) changed = true;
        if (kept.isNotEmpty) result.add(kept.length == appIds.length ? item : item.copyWith(appIds: kept));
      case WidgetItem():
        result.add(item);
    }
  }
  for (final id in installed) {
    if (seen.add(id)) {
      result.add(AppItem(id));
      changed = true;
    }
  }
  return changed ? result : items;
}

/// Where an item's top-left cell is.
@immutable
class GridSlot {
  const GridSlot(this.page, this.col, this.row);

  final int page;
  final int col;
  final int row;

  List<int> toJson() => [page, col, row];

  static GridSlot? fromJson(Object? json) {
    if (json is! List || json.length != 3) return null;
    final [p, c, r] = json;
    return (p is int && c is int && r is int) ? GridSlot(p, c, r) : null;
  }

  @override
  bool operator ==(Object other) => other is GridSlot && other.page == page && other.col == col && other.row == row;

  @override
  int get hashCode => Object.hash(page, col, row);

  @override
  String toString() => 'GridSlot($page, $col, $row)';
}

String encodeSlots(Map<String, GridSlot> slots) => jsonEncode({for (final e in slots.entries) e.key: e.value.toJson()});

Map<String, GridSlot> decodeSlots(String? raw) {
  if (raw == null) return {};
  try {
    return {for (final e in (jsonDecode(raw) as Map).entries) e.key as String: ?GridSlot.fromJson(e.value)};
  } catch (_) {
    return {};
  }
}

/// An item at its place on a page.
@immutable
class PlacedItem {
  const PlacedItem(this.item, this.slot, this.cols, this.rows);

  final HomeItem item;
  final GridSlot slot;

  /// Span actually used, clamped to the grid.
  final int cols;
  final int rows;

  int get page => slot.page;
  int get col => slot.col;
  int get row => slot.row;

  bool covers(int col, int row) => col >= slot.col && col < slot.col + cols && row >= slot.row && row < slot.row + rows;
}

/// [arrange]'s result: the pages, and every item's resolved slot.
class Arrangement {
  const Arrangement(this.pages, this.slots);

  final List<List<PlacedItem>> pages;
  final Map<String, GridSlot> slots;

  PlacedItem? find(String key) {
    for (final page in pages) {
      for (final p in page) {
        if (p.item.key == key) return p;
      }
    }
    return null;
  }
}

/// Puts [items] on pages of [columns] x [rows] cells, each at its saved slot
/// where possible, so items stay exactly where they were placed (gaps and all).
///
/// [priority] (the item just moved or resized) is placed first; then items in
/// list order. An item whose slot is taken, or that no longer fits, moves to
/// the nearest free spot from its page on. Items with no slot yet (new apps)
/// fill free spots from the last page on. Empty pages are dropped.
Arrangement arrange(
  List<HomeItem> items,
  Map<String, GridSlot> slots, {
  required int columns,
  required int rows,
  String? priority,
}) {
  final used = <int, List<List<bool>>>{};
  List<List<bool>> grid(int page) =>
      used.putIfAbsent(page, () => List.generate(rows, (_) => List.filled(columns, false)));

  bool fits(int page, int c, int r, int w, int h) {
    if (c < 0 || r < 0 || c + w > columns || r + h > rows) return false;
    final g = grid(page);
    for (var y = r; y < r + h; y++) {
      for (var x = c; x < c + w; x++) {
        if (g[y][x]) return false;
      }
    }
    return true;
  }

  final placed = <PlacedItem>[];
  void occupy(HomeItem item, GridSlot slot, int w, int h) {
    final g = grid(slot.page);
    for (var y = slot.row; y < slot.row + h; y++) {
      for (var x = slot.col; x < slot.col + w; x++) {
        g[y][x] = true;
      }
    }
    placed.add(PlacedItem(item, slot, w, h));
  }

  final ordered = [...items.where((i) => i.key == priority), ...items.where((i) => i.key != priority)];
  final pending = <(HomeItem, int)>[];
  final fresh = <HomeItem>[];
  for (final item in ordered) {
    final w = math.min(item.cols, columns);
    final h = math.min(item.rows, rows);
    final saved = slots[item.key];
    if (saved == null) {
      fresh.add(item);
      continue;
    }
    // Keep it on its page even if it grew past the edge: pull it back in.
    final c = math.min(saved.col, columns - w);
    final r = math.min(saved.row, rows - h);
    if (saved.page >= 0 && fits(saved.page, c, r, w, h)) {
      occupy(item, GridSlot(saved.page, c, r), w, h);
    } else {
      pending.add((item, math.max(saved.page, 0)));
    }
  }
  final lastPage = placed.fold(0, (m, p) => math.max(m, p.page));
  pending.addAll([for (final item in fresh) (item, lastPage)]);

  for (final (item, fromPage) in pending) {
    final w = math.min(item.cols, columns);
    final h = math.min(item.rows, rows);
    for (var page = fromPage; ; page++) {
      GridSlot? spot;
      search:
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < columns; c++) {
          if (fits(page, c, r, w, h)) {
            spot = GridSlot(page, c, r);
            break search;
          }
        }
      }
      if (spot != null) {
        occupy(item, spot, w, h);
        break;
      }
    }
  }

  // Drop empty pages, keeping page order.
  final pageNumbers = placed.map((p) => p.page).toSet().toList()..sort();
  final renumber = {for (final (i, p) in pageNumbers.indexed) p: i};
  final pages = List.generate(math.max(pageNumbers.length, 1), (_) => <PlacedItem>[]);
  final resolved = <String, GridSlot>{};
  for (final p in placed) {
    final slot = GridSlot(renumber[p.page]!, p.col, p.row);
    pages[slot.page].add(PlacedItem(p.item, slot, p.cols, p.rows));
    resolved[p.item.key] = slot;
  }
  return Arrangement(pages, resolved);
}

/// Where a [cols] × [rows] item fits in [arrangement] without moving
/// anything: the first free spot on [page], else on the other pages in
/// order, else the top of a new page after the last. Null if it's bigger
/// than a page of [columns] × [rows] cells.
GridSlot? freeSpot(
  Arrangement arrangement, {
  required int cols,
  required int rows,
  required int columns,
  required int gridRows,
  int page = 0,
}) {
  if (cols > columns || rows > gridRows) return null;
  final pageCount = arrangement.pages.length;
  for (final p in [
    if (page < pageCount) page,
    for (var i = 0; i < pageCount; i++)
      if (i != page) i,
  ]) {
    final placed = arrangement.pages[p];
    bool free(int c, int r) =>
        !placed.any((o) => c < o.col + o.cols && o.col < c + cols && r < o.row + o.rows && o.row < r + rows);
    for (var r = 0; r + rows <= gridRows; r++) {
      for (var c = 0; c + cols <= columns; c++) {
        if (free(c, r)) return GridSlot(p, c, r);
      }
    }
  }
  return GridSlot(pageCount, 0, 0);
}

/// Items other than [moved] that end up on a later page in [after] than in
/// [before]: pushed off their page by a change, rather than given room on
/// it. (Items only ever spill forward; pages emptied by the change shift
/// later ones back, which is fine.)
List<String> spilled(Arrangement before, Arrangement after, {String? moved}) => [
  for (final MapEntry(:key, :value) in before.slots.entries)
    if (key != moved && (after.slots[key]?.page ?? value.page) > value.page) key,
];
