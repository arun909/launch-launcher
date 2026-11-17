import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/app_info.dart';
import '../models/icon_shape.dart';
import '../models/icon_style.dart';

/// On-disk cache of the app list and icons, so cold start can render
/// immediately instead of waiting for PackageManager.
///
/// Layout (in the app support dir):
///   `app_cache/apps.json`         list of AppInfo metadata
///   `app_cache/icons/<hash>.png`  one PNG per app id
///   `app_cache/icon_shape.txt`    the [IconShape] those PNGs were rendered with
///   `app_cache/icon_style.txt`    [iconRendererVersion] and the [IconStyle] they were rendered with
/// Bump when the native icon drawing changes, so cached icons are redrawn
/// even though the user's settings are the same.
const iconRendererVersion = 4;

class AppCache {
  AppCache({Future<Directory> Function()? baseDir}) : _baseDir = baseDir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _baseDir;
  Directory? _root;

  Future<Directory> _dir() async {
    final root = _root ??= Directory('${(await _baseDir()).path}/app_cache');
    await Directory('${root.path}/icons').create(recursive: true);
    return root;
  }

  Future<File> _listFile() async => File('${(await _dir()).path}/apps.json');

  Future<File> _iconFile(String id) async => File('${(await _dir()).path}/icons/${_fileNameFor(id)}.png');

  /// Cached apps with icons attached, or an empty list if nothing is cached
  /// or the cache is unreadable.
  Future<List<AppInfo>> load() async {
    try {
      final file = await _listFile();
      if (!await file.exists()) return const [];
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      final apps = raw.map((e) => AppInfo.fromMap(e as Map<String, dynamic>)).toList();
      return await Future.wait(
        apps.map((app) async {
          final iconFile = await _iconFile(app.id);
          return await iconFile.exists() ? app.copyWith(icon: await iconFile.readAsBytes()) : app;
        }),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveList(List<AppInfo> apps) async {
    final file = await _listFile();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(apps.map((a) => a.toMap()).toList()));
    await tmp.rename(file.path); // atomic replace
  }

  Future<void> saveIcon(String id, Uint8List png) async => (await _iconFile(id)).writeAsBytes(png);

  Future<File> _shapeFile() async => File('${(await _dir()).path}/icon_shape.txt');

  /// Shape the cached icons were rendered with. Caches from before icon
  /// shapes existed have no file and were rendered as [IconShape.system].
  Future<IconShape> loadIconShape() async {
    try {
      final file = await _shapeFile();
      return await file.exists() ? IconShape.decode((await file.readAsString()).trim()) : IconShape.system;
    } catch (_) {
      return IconShape.system;
    }
  }

  Future<void> saveIconShape(IconShape shape) async => (await _shapeFile()).writeAsString(shape.encode());

  Future<File> _styleFile() async => File('${(await _dir()).path}/icon_style.txt');

  /// Style the cached icons were rendered with, or null if they were drawn by
  /// another [iconRendererVersion] (or the cache predates icon styles).
  Future<IconStyle?> loadIconStyle() async {
    try {
      final file = await _styleFile();
      if (!await file.exists()) return null;
      final [version, style] = (await file.readAsString()).split('\n');
      return version == '$iconRendererVersion' ? IconStyle.decode(style) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveIconStyle(IconStyle style) async =>
      (await _styleFile()).writeAsString('$iconRendererVersion\n${style.encode()}');

  /// Deletes icon files that don't belong to any of [keepIds].
  Future<void> pruneIcons(Iterable<String> keepIds) async {
    final keep = keepIds.map((id) => '${_fileNameFor(id)}.png').toSet();
    final iconsDir = Directory('${(await _dir()).path}/icons');
    await for (final entity in iconsDir.list()) {
      if (entity is File && !keep.contains(entity.uri.pathSegments.last)) {
        await entity.delete();
      }
    }
  }

  Future<void> clear() async {
    final root = await _dir();
    await root.delete(recursive: true);
  }

  /// Ids contain '/' and can be long; map them to a short, stable file name
  /// (64-bit FNV-1a hash of the id).
  static String _fileNameFor(String id) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(id)) {
      hash ^= byte;
      hash *= 0x100000001b3;
    }
    return hash.toUnsigned(64).toRadixString(16);
  }
}
