import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/home_grid.dart';

import '../../core/apps/apps_controller.dart';
import '../../core/models/icon_shape.dart';
import '../widgets/home_widget_view.dart';
import '../widgets/launcher_widgets.dart';
import 'home_layout.dart';

/// How the home screen shows apps.
enum HomeMode {
  /// Only chosen apps on home; everything else in the swipe-up drawer.
  drawer('App drawer'),

  /// Every app on swipeable home pages, groupable into containers.
  standard('Standard');

  const HomeMode(this.label);
  final String label;
}

/// A standard-mode layout as it was, to put back with
/// [HomeLayoutController.restore].
typedef HomeLayoutSnapshot = ({List<HomeItem> items, Map<String, GridSlot> slots});

/// The home mode, and the standard-mode page layout. Stored in the launcher's
/// own prefs only.
///
/// The layout always holds every installed app exactly once (see
/// [syncWithInstalled]); hidden and dock apps keep their place but are left
/// out when drawn, so unhiding or un-docking puts them back where they were.
///
/// Each item's position is a saved [GridSlot]; [arrange] turns items + slots
/// into pages, moving aside whatever a moved or resized item now overlaps.
class HomeLayoutController extends ChangeNotifier {
  HomeLayoutController(this._prefs, this._apps)
    : _mode = HomeMode.values.asNameMap()[_prefs.getString(_modeKey)] ?? HomeMode.drawer,
      _items = decodeLayout(_prefs.getString(_layoutKey)),
      _slots = decodeSlots(_prefs.getString(_slotsKey)),
      _grid = HomeGrid.fromName(_prefs.getString(_gridKey)),
      _showLabels = _prefs.getBool(_labelsKey) ?? true {
    HomeGrid.iconScale = (_prefs.getDouble(_iconScaleKey) ?? 1).clamp(HomeGrid.minIconScale, HomeGrid.maxIconScale);
    _dropRemovedLauncherWidgets();
    _apps.addListener(_sync);
    _sync();
  }

  /// Launcher widgets whose kind the launcher no longer has (removed in an
  /// update) leave the home screen rather than show as blank panels.
  void _dropRemovedLauncherWidgets() {
    var changed = false;
    final kept = <HomeItem>[
      for (final i in _items)
        if (!(i is WidgetItem && i.launcherKind != null && LauncherWidgetKind.fromName(i.launcherKind) == null))
          _withKindLimits(i),
    ];
    for (var n = 0; n < kept.length && !changed; n++) {
      changed = !identical(kept[n], _items[n]);
    }
    if (changed || kept.length != _items.length) _set(kept);
  }

  /// A launcher widget held to its kind's current limits and sizes (they
  /// may have changed in an update); anything else as it is.
  static HomeItem _withKindLimits(HomeItem i) {
    if (i is! WidgetItem) return i;
    final kind = LauncherWidgetKind.fromName(i.launcherKind);
    if (kind == null) return i;
    final limited = i.copyWith(minCols: kind.min.$1, minRows: kind.min.$2, maxCols: kind.max.$1, maxRows: kind.max.$2);
    final (cols, rows) = kind.snap(limited.cols, limited.rows);
    final next = limited.copyWith(cols: cols, rows: rows);
    return next == i ? i : next;
  }

  static const _modeKey = 'home_mode';
  static const _layoutKey = 'standard_home_layout';
  static const _slotsKey = 'standard_home_slots';
  static const _gridKey = 'home_grid';
  static const _iconScaleKey = 'home_icon_scale';
  static const _labelsKey = 'home_labels';

  final SharedPreferences _prefs;
  final AppsController _apps;
  HomeMode _mode;
  List<HomeItem> _items;
  final Map<String, GridSlot> _slots;

  /// The item last moved or resized: it keeps its spot and others make room.
  String? _priority;

  HomeMode get mode => _mode;

  /// Apps per row, and the icon / label sizes that go with it.
  HomeGrid get grid => _grid;
  HomeGrid _grid;

  /// App icon size, as a factor of the grid's (see HomeGrid.iconScale):
  /// everywhere home icons are drawn (home, folders, dock, drawer).
  double get iconScale => HomeGrid.iconScale;

  Future<void> setIconScale(double scale) async {
    final v = (scale.clamp(HomeGrid.minIconScale, HomeGrid.maxIconScale) * 100).roundToDouble() / 100;
    if (v == HomeGrid.iconScale) return;
    HomeGrid.iconScale = v;
    notifyListeners();
    await _prefs.setDouble(_iconScaleKey, v);
  }

  /// With another number of columns, the home pages are re-flowed (see
  /// [_reflow]); with the same, everything stays where it is.
  Future<void> setGrid(HomeGrid grid) async {
    if (grid == _grid) return;
    final reflow = grid.columns != _grid.columns;
    _grid = grid;
    _selected = null;
    if (reflow) {
      _reflow();
    } else {
      notifyListeners();
    }
    await _prefs.setString(_gridKey, grid.name);
  }

  /// Packs everything again in reading order (page by page, row by row, as
  /// it was placed), filling the new rows from the first page with no holes,
  /// as Android's own launcher does when its grid changes. Keeping the old
  /// spots instead left a column empty on a wider grid, and on a narrower
  /// one pushed whatever no longer fit into scattered free spots.
  void _reflow() {
    final indexed = _items.indexed.toList();
    int compare((int, HomeItem) a, (int, HomeItem) b) {
      final (sa, sb) = (_slots[a.$2.key], _slots[b.$2.key]);
      if (sa != null && sb != null) {
        for (final (x, y) in [(sa.page, sb.page), (sa.row, sb.row), (sa.col, sb.col)]) {
          if (x != y) return x.compareTo(y);
        }
      } else if (sa != null || sb != null) {
        return sa != null ? -1 : 1; // never placed (new apps): after the rest
      }
      return a.$1.compareTo(b.$1); // keeps the order otherwise (sort isn't stable)
    }

    indexed.sort(compare);
    _slots.clear();
    _priority = null;
    _set([for (final (_, item) in indexed) item]);
  }

  /// App names under home-screen icons (both modes). Off: icons only, in
  /// the same spots. The drawer and search always show names.
  bool get showLabels => _showLabels;
  bool _showLabels;

  Future<void> setShowLabels(bool show) async {
    if (show == _showLabels) return;
    _showLabels = show;
    notifyListeners();
    await _prefs.setBool(_labelsKey, show);
  }

  /// The shape app icons are drawn with; folders and containers keep their
  /// corners round enough to still fit them (see AppContainerTile).
  IconShape get iconShape => _apps.iconShape;

  List<HomeItem> get items => _items;
  Map<String, GridSlot> get slots => Map.unmodifiable(_slots);
  String? get priority => _priority;

  /// Size of one grid cell on the home screen, as last laid out. Lets the
  /// container editor preview at true scale. Not saved.
  Size cellSize = const Size(88, 100);

  /// Size of the home grid area, as last laid out (for showing how many rows
  /// each grid preset gets on this phone). Not saved.
  Size gridArea = const Size(396, 700);

  /// The standard-mode page on screen (where new widgets go). Not saved.
  int currentPage = 0;

  /// The standard-mode pages as last drawn, and how many rows each has (for
  /// finding room for a new widget; see [freeSpot]). Not saved.
  Arrangement? arrangement;
  int gridRows = 6;

  /// A page StandardHome should show next (a widget just went there).
  int? pageRequest;

  /// Where a [cols] × [rows] widget fits on the home pages as they are,
  /// moving nothing: on the page on screen if it can, else another page,
  /// else a new one. Null if it's bigger than a page.
  GridSlot? roomFor(int cols, int rows) {
    final a = arrangement ?? const Arrangement([[]], {});
    return freeSpot(a, cols: cols, rows: rows, columns: _grid.columns, gridRows: gridRows, page: currentPage);
  }

  /// Edit mode: items can be dragged around. Not saved.
  bool get editing => _editing;
  bool _editing = false;

  void setEditing(bool editing) {
    if (editing == _editing) return;
    _editing = editing;
    _selected = null;
    notifyListeners();
  }

  /// True while an item is being dragged. Not saved.
  bool get dragging => _dragging;
  bool _dragging = false;

  void setDragging(bool dragging) {
    if (dragging == _dragging) return;
    _dragging = dragging;
    notifyListeners();
  }

  /// Edit mode as it was before the current drag.
  bool _editingBeforeDrag = false;

  /// A drag begins: edit mode for its length, so items show as movable.
  void beginDrag() {
    if (_dragging) return;
    _editingBeforeDrag = _editing;
    _dragging = true;
    if (!_editing) {
      _editing = true;
      _selected = null;
    }
    notifyListeners();
  }

  /// Ends the drag when the finger lifts, then runs [then]. For drags whose
  /// source leaves the screen mid-drag (an app out of a folder, out of the
  /// dock): Flutter no longer reports such a drag's end to its source.
  void endDragOnRelease({VoidCallback? then}) {
    late final PointerRoute ended;
    ended = (event) {
      if (event is PointerUpEvent || event is PointerCancelEvent) {
        GestureBinding.instance.pointerRouter.removeGlobalRoute(ended);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          endDrag();
          then?.call();
        });
      }
    };
    GestureBinding.instance.pointerRouter.addGlobalRoute(ended);
  }

  /// The drag is over: back to how it was. A drag from the normal home
  /// screen leaves no edit mode behind, so there's nothing to confirm.
  void endDrag() {
    if (!_dragging) return;
    _dragging = false;
    if (!_editingBeforeDrag) {
      _editing = false;
      _selected = null;
    }
    notifyListeners();
  }

  /// The folder / container selected for resizing in edit mode. Not saved.
  String? get selected => _selected;
  String? _selected;

  void select(String? key) {
    if (key == _selected) return;
    _selected = key;
    notifyListeners();
  }

  /// True while a resize / radius handle is held. Positions that neighbours
  /// were pushed to aren't fixed until it's let go, so shrinking back lets
  /// them return.
  bool get interacting => _interacting;
  bool _interacting = false;

  void setInteracting(bool active) {
    if (active == _interacting) return;
    _interacting = active;
    notifyListeners();
    if (!active) _save(); // Saved once on release, not on every step.
  }

  @override
  void dispose() {
    _apps.removeListener(_sync);
    super.dispose();
  }

  Future<void> setMode(HomeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    _editing = false;
    notifyListeners();
    await _prefs.setString(_modeKey, mode.name);
  }

  /// The container holding [appId], if any.
  AppContainer? containerOf(String appId) {
    for (final item in _items) {
      if (item is AppContainer && item.appIds.contains(appId)) return item;
    }
    return null;
  }

  AppContainer? container(String id) {
    for (final item in _items) {
      if (item is AppContainer && item.id == id) return item;
    }
    return null;
  }

  Iterable<AppContainer> get containers => _items.whereType<AppContainer>();

  /// Drag and drop: puts the item with [key] at [slot]; whatever it now
  /// overlaps moves to the nearest free spot.
  ///
  /// With [swapKey], that item (the one dropped on) takes [swapTo], the spot
  /// the moved item came from: the two trade places.
  ///
  /// An app dragged out of a folder / container leaves it and goes on the
  /// page on its own (a container left empty is removed).
  void place(String key, GridSlot slot, {String? swapKey, GridSlot? swapTo}) {
    var items = _items;
    if (key.startsWith('app:') && containerOf(key.substring(4)) != null) {
      final appId = key.substring(4);
      items = [..._without(appId), AppItem(appId)];
    }
    _slots[key] = slot;
    if (swapKey != null && swapTo != null) _slots[swapKey] = swapTo;
    _priority = key;
    _set(items);
  }

  /// From a folder / container's handles: its new position, size or corner
  /// radius. Neighbours make room.
  void reshape(GridSlot slot, AppContainer updated) {
    final i = _items.indexWhere((c) => c is AppContainer && c.id == updated.id);
    if (i < 0) return;
    _slots[updated.key] = slot;
    _priority = updated.key;
    _set([..._items]..[i] = updated);
  }

  /// Removes every folder and container and lines all apps up in
  /// alphabetical order, packed from the first page. Widgets stay, first.
  ///
  /// Returns the layout it replaced, for [restore] (undo).
  HomeLayoutSnapshot tidyUp() {
    final before = (items: _items, slots: Map.of(_slots));
    _slots.clear();
    _priority = null;
    _selected = null;
    // [syncWithInstalled] on an empty layout = every app, in the (alphabetical)
    // order of the app list.
    _set([
      ...widgets,
      ...syncWithInstalled(const [], [for (final a in _apps.apps) a.id]),
    ]);
    return before;
  }

  /// Puts back a layout from [tidyUp], brought up to date with the
  /// installed apps.
  void restore(HomeLayoutSnapshot snapshot) {
    _slots
      ..clear()
      ..addAll(snapshot.slots);
    _priority = null;
    _selected = null;
    _set(snapshot.items);
    _sync();
  }

  Iterable<WidgetItem> get widgets => _items.whereType<WidgetItem>();

  WidgetItem? findWidget(String id) => widgets.where((w) => w.id == id).firstOrNull;

  /// Puts [widget] on the home screen: in standard mode at [at] (see
  /// [roomFor]; by default the first free spot from the page on screen),
  /// in drawer mode after the other widgets. Nothing is pushed aside.
  void addWidget(WidgetItem widget, {GridSlot? at}) {
    // A slot that's taken sends it to the nearest free one from that page on
    // (see [arrange]); not the priority, so it doesn't move others.
    _slots[widget.key] = at ?? GridSlot(currentPage, 0, 0);
    if (at != null && at.page != currentPage) pageRequest = at.page;
    _set([..._items, widget]);
  }

  /// Works app widgets' cell limits out again for cells of [cell] (after a
  /// grid change, or on another screen size), growing or shrinking any that
  /// no longer have the room they need, or have more than they allow (see
  /// HomeWidgetView.fitTo). Does nothing if all still fit. True if any changed.
  bool fitWidgetsTo(Size cell) {
    var changed = false;
    final items = [
      for (final i in _items)
        if (i is WidgetItem)
          () {
            final fitted = HomeWidgetView.fitTo(i, _grid, cell);
            if (fitted != i) changed = true;
            return fitted;
          }()
        else
          i,
    ];
    if (changed) _set(items);
    return changed;
  }

  /// From a widget's handles: its new position and size. Neighbours make
  /// room (StandardHome first checks they can, on the same page).
  void reshapeWidget(GridSlot slot, WidgetItem updated) {
    final i = _items.indexWhere((w) => w is WidgetItem && w.id == updated.id);
    if (i < 0) return;
    _slots[updated.key] = slot;
    _priority = updated.key;
    _set([..._items]..[i] = updated);
  }

  /// New span for widget [id]; neighbours make room.
  void resizeWidget(String id, {required int cols, required int rows}) {
    final i = _items.indexWhere((w) => w is WidgetItem && w.id == id);
    if (i < 0) return;
    final w = _items[i] as WidgetItem;
    final (c, r) = snapSpan(w, cols, rows, gridColumns: _grid.columns);
    final updated = w.copyWith(cols: c, rows: r);
    if (updated == _items[i]) return;
    _priority = updated.key;
    _set([..._items]..[i] = updated);
  }

  /// New options for launcher widget [id] (its look; see WidgetItem.settings).
  void updateWidgetSettings(String id, Map<String, dynamic> settings) {
    final i = _items.indexWhere((w) => w is WidgetItem && w.id == id);
    if (i < 0) return;
    final updated = (_items[i] as WidgetItem).copyWith(settings: settings);
    if (updated == _items[i]) return;
    _set([..._items]..[i] = updated);
  }

  /// Takes widget [id] off the home screen. (An app widget's Android id is
  /// released by the caller; see AppWidgetsPlatform.)
  void removeWidget(String id) {
    if (_selected == 'widget:$id') _selected = null;
    _set([
      for (final i in _items)
        if (!(i is WidgetItem && i.id == id)) i,
    ]);
  }

  /// Saves the positions [arrange] resolved, so they stay fixed from now on.
  /// Doesn't notify: the arrangement on screen is already this.
  void commitSlots(Map<String, GridSlot> resolved) {
    _priority = null;
    var changed = false;
    for (final MapEntry(:key, :value) in resolved.entries) {
      if (_slots[key] != value) {
        _slots[key] = value;
        changed = true;
      }
    }
    if (changed) _prefs.setString(_slotsKey, encodeSlots(_slots));
  }

  /// Turns [appId]'s home icon into a new container (or [folder]) holding it,
  /// in its place. Returns the new group's id.
  String createContainer(String appId, {String? name, bool folder = false}) {
    final id = newId();
    final container = AppContainer(
      id: id,
      name: name ?? (folder ? 'Folder' : 'Apps'),
      appIds: [appId],
      cols: folder ? 1 : 2,
      rows: folder ? 1 : 2,
      cornerRadius: folder ? defaultFolderRadius : AppContainer.defaultCornerRadius,
    );
    final items = _without(appId);
    final at = _items.indexWhere((i) => i is AppItem && i.appId == appId);
    items.insert(at < 0 ? items.length : at.clamp(0, items.length), container);
    // Takes the app's spot; whatever its bigger size covers makes room.
    if (_slots.remove(AppItem(appId).key) case final slot?) _slots[container.key] = slot;
    _priority = container.key;
    _set(items);
    return id;
  }

  /// A fresh id for a container or widget.
  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// Drag and drop: [draggedAppId] dropped onto [targetAppId] makes a folder
  /// of the two, in the target's place.
  String? createFolder(String targetAppId, String draggedAppId) {
    if (targetAppId == draggedAppId) return null;
    final id = createContainer(targetAppId, folder: true);
    addToContainer(id, draggedAppId);
    return id;
  }

  /// Default roundness for new folders: a rounded square, like app icons.
  /// New folders start fully rounded (the "Rounded" step; see
  /// AppContainerTile.radiiFor, which draws them at the most that fits).
  static const defaultFolderRadius = AppContainer.maxCornerRadius;

  /// Moves [appId] into the container [containerId], from wherever it was.
  void addToContainer(String containerId, String appId) {
    final items = _without(appId);
    _slots.remove(AppItem(appId).key);
    final i = items.indexWhere((c) => c is AppContainer && c.id == containerId);
    if (i < 0) return;
    final c = items[i] as AppContainer;
    items[i] = c.copyWith(appIds: [...c.appIds, appId]);
    _set(items);
  }

  /// Takes [appId] out of its container and puts it on the page right after it.
  void removeFromContainer(String appId) {
    final c = containerOf(appId);
    if (c == null) return;
    setContainerApps(c.id, [
      for (final id in c.appIds)
        if (id != appId) id,
    ]);
  }

  /// Sets exactly which apps [containerId] holds, in order. Apps added are
  /// taken from wherever they were; apps removed go on the page right after
  /// the container. A container left empty is removed.
  void setContainerApps(String containerId, List<String> appIds) {
    final current = container(containerId);
    if (current == null) return;
    final removed = [
      for (final id in current.appIds)
        if (!appIds.contains(id)) id,
    ];
    var items = [..._items];
    for (final id in appIds) {
      if (!current.appIds.contains(id)) items = _without(id, items);
    }
    final i = items.indexWhere((c) => c is AppContainer && c.id == containerId);
    final released = [for (final id in removed) AppItem(id)];
    // Released apps go where the container is (the first one exactly, if the
    // container is gone); the rest move to the nearest free spots from there.
    if (_slots[current.key] case final slot?) {
      for (final app in released) {
        _slots[app.key] = slot;
      }
      if (appIds.isEmpty && released.isNotEmpty) _priority = released.first.key;
    }
    if (appIds.isEmpty) {
      items.replaceRange(i, i + 1, released);
    } else {
      items[i] = current.copyWith(appIds: appIds);
      items.insertAll(i + 1, released);
    }
    _set(items);
  }

  /// Puts [containerId]'s apps in [order] (dragged around in the open
  /// container). Apps it holds that [order] leaves out (hidden ones the
  /// open container didn't show) keep their order after it.
  void reorderContainer(String containerId, List<String> order) {
    final i = _items.indexWhere((c) => c is AppContainer && c.id == containerId);
    if (i < 0) return;
    final c = _items[i] as AppContainer;
    final front = order.where(c.appIds.contains).toList();
    final reordered = [...front, ...c.appIds.where((id) => !front.contains(id))];
    if (listEquals(reordered, c.appIds)) return;
    _set([..._items]..[i] = c.copyWith(appIds: reordered));
  }

  /// Replaces the container with its apps, in its place.
  void ungroup(String containerId) => setContainerApps(containerId, const []);

  /// Saves changed settings (name, size, preview count, radius) of a container.
  void updateContainer(AppContainer updated) {
    final i = _items.indexWhere((c) => c is AppContainer && c.id == updated.id);
    if (i < 0) return;
    _priority = updated.key; // Resized: it stays, neighbours make room.
    _set([..._items]..[i] = updated);
  }

  /// Every folder / container takes [style] (and [color], for a colour tint).
  void styleAllContainers(GroupStyle style, int color) {
    _set([
      for (final item in _items)
        item is AppContainer ? item.copyWith(style: style, color: color) : item,
    ]);
  }

  /// [items] (default: the current layout) with [appId] taken out of wherever
  /// it is; containers left empty are dropped.
  List<HomeItem> _without(String appId, [List<HomeItem>? items]) {
    final result = <HomeItem>[];
    for (final item in items ?? _items) {
      switch (item) {
        case AppItem(appId: final id) when id == appId:
          break;
        case AppContainer(:final appIds) when appIds.contains(appId):
          final rest = [
            for (final id in appIds)
              if (id != appId) id,
          ];
          if (rest.isNotEmpty) result.add(item.copyWith(appIds: rest));
        default:
          result.add(item);
      }
    }
    return result;
  }

  void _sync() {
    // Only against a real app list: an empty one (not loaded yet) would wipe
    // the layout.
    if (!_apps.isLoaded || _apps.apps.isEmpty) return;
    final synced = syncWithInstalled(_items, [for (final a in _apps.apps) a.id]);
    if (!identical(synced, _items)) _set(synced);
  }

  void _set(List<HomeItem> items) {
    // Containers always fit their apps (see AppContainer.fitted): one that
    // lost apps shrinks rather than leaving blank cells.
    _items = List.unmodifiable([for (final i in items) i is AppContainer ? i.fitted() : i]);
    final keys = {for (final i in _items) i.key};
    _slots.removeWhere((key, _) => !keys.contains(key));
    notifyListeners();
    // While a handle is held, changes come many times a second; save once
    // it's let go (see [setInteracting]).
    if (!_interacting) _save();
  }

  void _save() {
    _prefs.setString(_layoutKey, encodeLayout(_items));
    _prefs.setString(_slotsKey, encodeSlots(_slots));
  }
}
