import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One site pinned to the Chrome widget.
@immutable
class ChromeSite {
  const ChromeSite({required this.name, required this.url});

  /// From what was typed: [address] gets `https://` if it has no scheme;
  /// an empty [name] becomes the site's own ("youtube.com" → "Youtube").
  factory ChromeSite.typed(String address, String name) {
    var url = address.trim();
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(url)) url = 'https://$url';
    final label = name.trim();
    return ChromeSite(name: label.isEmpty ? nameOf(url) : label, url: url);
  }

  factory ChromeSite.fromJson(Map<String, dynamic> json) =>
      ChromeSite(name: json['name'] as String? ?? '', url: json['url'] as String? ?? '');

  final String name;
  final String url;

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  /// "https://www.youtube.com/feed" → "Youtube".
  static String nameOf(String url) {
    var host = Uri.tryParse(url)?.host ?? url;
    if (host.startsWith('www.')) host = host.substring(4);
    final first = host.split('.').first;
    return first.isEmpty ? url : first[0].toUpperCase() + first.substring(1);
  }

  /// Its host without `www.`, lower case: what its icon is kept under.
  String get host {
    var h = (Uri.tryParse(url)?.host ?? '').toLowerCase();
    if (h.startsWith('www.')) h = h.substring(4);
    return h;
  }

  /// The site's address without scheme and `www.`, for showing.
  String get shortUrl => url.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://(www\.)?'), '');

  @override
  bool operator ==(Object other) => other is ChromeSite && other.name == name && other.url == url;

  @override
  int get hashCode => Object.hash(name, url);
}

/// The sites pinned to the Chrome widget (up to [max]), shared by every
/// Chrome widget, which shows as many as its size fits, in order; and their
/// icons, fetched from each site itself (see [SiteIconFetcher]) and kept
/// on the phone.
class ChromeSitesController extends ChangeNotifier {
  ChromeSitesController(this._prefs) : _sites = _load(_prefs) {
    _loadIcons();
  }

  static const max = 15;
  static const _key = 'chrome_widget_sites';

  final SharedPreferences _prefs;
  List<ChromeSite> _sites;

  List<ChromeSite> get sites => List.unmodifiable(_sites);

  bool get isFull => _sites.length >= max;

  static List<ChromeSite> _load(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => ChromeSite.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((s) => s.url.isNotEmpty)
          .take(max)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(ChromeSite site) async {
    if (isFull) return;
    await _save([..._sites, site]);
    _fetchIcon(site.host);
  }

  Future<void> replace(int index, ChromeSite site) async {
    if (index < 0 || index >= _sites.length) return;
    await _save([..._sites]..[index] = site);
    _fetchIcon(site.host);
  }

  Future<void> remove(int index) async {
    if (index < 0 || index >= _sites.length) return;
    await _save([..._sites]..removeAt(index));
  }

  /// Moves the site at [from] to index [to] of the new order (ReorderableListView.onReorderItem).
  Future<void> move(int from, int to) async {
    final list = [..._sites];
    final site = list.removeAt(from);
    list.insert(to.clamp(0, list.length), site);
    await _save(list);
  }

  // ---- Icons -----------------------------------------------------------

  final _icons = <String, File>{};
  final _fetching = <String>{};
  Directory? _iconDir;

  /// [site]'s icon on the phone, or null while there's none (yet).
  File? iconOf(ChromeSite site) => _icons[site.host];

  Future<Directory?> _dir() async {
    if (_iconDir != null) return _iconDir;
    try {
      final d = Directory('${(await getApplicationSupportDirectory()).path}/site_icons');
      await d.create(recursive: true);
      return _iconDir = d;
    } catch (_) {
      return null; // No platform (tests).
    }
  }

  File _fileFor(Directory dir, String host) => File('${dir.path}/${host.replaceAll(RegExp(r'[^a-z0-9.-]'), '_')}.img');

  /// The icons already kept; fetches the missing ones.
  Future<void> _loadIcons() async {
    final dir = await _dir();
    if (dir == null) return;
    var found = false;
    for (final s in _sites) {
      final f = _fileFor(dir, s.host);
      if (await f.exists()) {
        _icons[s.host] = f;
        found = true;
      } else {
        _fetchIcon(s.host);
      }
    }
    if (found) notifyListeners();
  }

  /// Fetches [host]'s icon unless it's kept or being fetched.
  Future<void> _fetchIcon(String host) async {
    if (host.isEmpty || _icons.containsKey(host) || !_fetching.add(host)) return;
    try {
      final dir = await _dir();
      if (dir == null) return;
      final bytes = await SiteIconFetcher.fetch(host);
      if (bytes == null) return;
      final f = _fileFor(dir, host);
      await f.writeAsBytes(bytes, flush: true);
      _icons[host] = f;
      notifyListeners();
    } catch (_) {
      // No icon: the tile shows the site's initial.
    } finally {
      _fetching.remove(host);
    }
  }

  Future<void> _save(List<ChromeSite> sites) async {
    _sites = sites;
    notifyListeners();
    await _prefs.setString(_key, jsonEncode([for (final s in sites) s.toJson()]));
  }
}

/// Finds a site's icon on the site itself (nothing else is asked): the
/// icons its home page links to (Apple touch icons and the largest
/// declared first), then `/apple-touch-icon.png`, then `/favicon.ico`.
/// The first that decodes at 64 px or more wins, else the biggest found.
class SiteIconFetcher {
  // A desktop browser's: desktop pages declare more (and larger) icons.
  static const _ua =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

  static Future<Uint8List?> fetch(String host) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = _ua;
    try {
      final home = Uri.https(host, '/');
      final candidates = <Uri>[];
      final page = await _get(client, home, limit: 400 * 1024);
      if (page != null) candidates.addAll(_declared(utf8.decode(page, allowMalformed: true), home));
      candidates
        ..add(home.resolve('/apple-touch-icon.png'))
        ..add(home.resolve('/favicon.ico'));

      Uint8List? best;
      var bestSize = 0;
      for (final uri in candidates.toSet().take(6)) {
        final bytes = await _get(client, uri, limit: 1024 * 1024);
        if (bytes == null) continue;
        final size = await _decodedSize(bytes);
        if (size > bestSize) {
          best = bytes;
          bestSize = size;
        }
        if (size >= 64) break;
      }
      return bestSize >= 16 ? best : null;
    } finally {
      client.close(force: true);
    }
  }

  /// The icons [html] links to, best first (SVGs skipped: they don't decode).
  static List<Uri> _declared(String html, Uri base) {
    final found = <(Uri, int)>[];
    String? attr(String tag, String name) {
      final m = RegExp('\\b$name\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false).firstMatch(tag);
      return m == null ? null : (m.group(2) ?? m.group(3) ?? m.group(4));
    }

    for (final m in RegExp(r'<link\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final tag = m.group(0)!;
      final rel = attr(tag, 'rel')?.toLowerCase() ?? '';
      final href = attr(tag, 'href');
      if (href == null || href.isEmpty || !rel.contains('icon') || rel.contains('mask')) continue;
      if (href.toLowerCase().contains('.svg') || (attr(tag, 'type') ?? '').contains('svg')) continue;
      final uri = Uri.tryParse(href.replaceAll('&amp;', '&'));
      if (uri == null) continue;
      final sizes = RegExp(r'(\d+)\s*x\s*\d+', caseSensitive: false).firstMatch(attr(tag, 'sizes') ?? '');
      final size = sizes != null ? int.parse(sizes.group(1)!) : (rel.contains('apple') ? 180 : 32);
      found.add((base.resolveUri(uri), size));
    }
    found.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (u, _) in found) u];
  }

  /// The image's width once decoded, or 0 if it isn't one.
  static Future<int> _decodedSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      frame.image.dispose();
      codec.dispose();
      return w;
    } catch (_) {
      return 0;
    }
  }

  static Future<Uint8List?> _get(HttpClient client, Uri uri, {required int limit}) async {
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        response.listen(null).cancel().ignore();
        return null;
      }
      final out = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        out.add(chunk);
        if (out.length > limit) break;
      }
      return out.takeBytes();
    } catch (_) {
      return null;
    }
  }
}
