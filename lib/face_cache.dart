import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// On-disk cache for tile faces (custom photos and Mulberry AAC symbol PNGs).
///
/// HARD RULE (Jeremy, 2026-10-26): a tile NEVER fetches an image while it
/// renders. Hundreds of kiosk tablets each starting an HTTP request on every
/// tile draw will hammer the API for no reason. Images are downloaded ONLY
/// during a config refresh (app launch sync, the manual Sync button, or the
/// 6-hourly auto sync), written into app-private storage, and rendered from
/// disk from then on.
///
/// Consequences, all deliberate:
///   * A tile with no cached face draws its emoji immediately — no spinner,
///     no waiting, no network. This is what makes the app work on a school
///     network that accepts connections and then hangs them.
///   * A URL already on disk is never re-requested, so the server only serves
///     each image once per tablet, not once per tile per frame.
///   * URLs that returned 404/410 are remembered as "missing" and never
///     retried, so emoji-only tiles (digits, symbols that have no PNG) do not
///     generate pointless requests on every refresh.
class FaceCache {
  FaceCache._();
  static final FaceCache instance = FaceCache._();

  Directory? _root;
  bool _loaded = false;

  /// remote URL -> absolute local file path
  final Map<String, String> _paths = <String, String>{};

  /// remote URLs known to be absent on the server (404/410) — never retried
  final Set<String> _missing = <String>{};

  static const String _subdir = 'faces';
  static const String _indexName = 'index.json';
  static const String _missingName = 'missing.json';

  Future<Directory> _dir() async {
    if (_root != null) return _root!;
    Directory d;
    try {
      final docs = await getApplicationDocumentsDirectory();
      d = Directory('${docs.path}/$_subdir');
      if (!d.existsSync()) d.createSync(recursive: true);
    } catch (_) {
      d = Directory.systemTemp.createTempSync('taptosay_faces');
    }
    _root = d;
    return d;
  }

  /// Load the on-disk index. Safe to call repeatedly; does real work once.
  /// Call this at startup BEFORE the first tile is built.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final d = await _dir();

    final idx = File('${d.path}/$_indexName');
    if (idx.existsSync()) {
      try {
        final m = jsonDecode(idx.readAsStringSync());
        if (m is Map) {
          m.forEach((k, v) {
            final p = v?.toString();
            if (p == null || p.isEmpty) return;
            // Drop entries whose file was deleted (cache cleared, low storage).
            if (File(p).existsSync()) _paths[k.toString()] = p;
          });
        }
      } catch (_) {
        // corrupt index — start clean, images will re-download on next refresh
      }
    }

    final miss = File('${d.path}/$_missingName');
    if (miss.existsSync()) {
      try {
        final l = jsonDecode(miss.readAsStringSync());
        if (l is List) {
          for (final e in l) {
            if (e != null) _missing.add(e.toString());
          }
        }
      } catch (_) {}
    }
  }

  /// Local file path for [url], or null when it is not on disk.
  ///
  /// This is the ONLY method the render path may call. It performs no I/O
  /// beyond a synchronous map lookup.
  String? pathFor(String? url) {
    if (url == null || url.isEmpty) return null;
    return _paths[url];
  }

  /// Whether [url] is already stored locally.
  bool has(String? url) => pathFor(url) != null;

  /// Download every URL in [urls] that is not already cached.
  ///
  /// Called ONLY from a config refresh — never from a build method. Returns the
  /// number of images newly written. Network failures are swallowed: the tile
  /// keeps showing its emoji until a later refresh succeeds.
  Future<int> syncAll(
    Iterable<String?> urls, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await load();
    final d = await _dir();

    final pending = <String>{};
    for (final u in urls) {
      if (u == null || u.isEmpty) continue;
      if (_paths.containsKey(u)) continue; // already have it — never re-fetch
      if (_missing.contains(u)) continue; // known 404 — never retry
      pending.add(u);
    }
    final all = urls.where((u) => u != null && u.isNotEmpty).toList();
    debugPrint('[faces] dir=${d.path} cached=${_paths.length} missing=${_missing.length} urls=${all.length} pending=${pending.length}');
    if (_paths.isNotEmpty) {
      final k = _paths.keys.first;
      debugPrint('[faces] sample key=$k');
      debugPrint('[faces] sample path=${_paths[k]} exists=${File(_paths[k]!).existsSync()}');
    }
    if (all.isNotEmpty) debugPrint('[faces] first url=${all.first}');
    if (pending.isNotEmpty) {
      debugPrint('[faces] first=${pending.first}');
    }
    if (pending.isEmpty) return 0;

    final client = HttpClient()..connectionTimeout = timeout;
    var written = 0;
    var missingChanged = false;

    for (final url in pending) {
      final file = File('${d.path}/${_safeName(url)}');
      try {
        final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
        final res = await req.close().timeout(timeout);

        if (res.statusCode == 404 || res.statusCode == 410) {
          await res.drain<void>().catchError((_) {});
          _missing.add(url);
          missingChanged = true;
          continue;
        }
        if (res.statusCode != 200) {
          await res.drain<void>().catchError((_) {});
          continue; // transient (5xx / 403) — try again next refresh
        }

        final bytes =
            await consolidateHttpClientResponseBytes(res).timeout(timeout);
        if (bytes.isEmpty) continue;

        file.writeAsBytesSync(bytes, flush: true);
        _paths[url] = file.path;
        written++;
      } catch (e) {
        debugPrint('[faces] FAIL $url -> $e');
        // timeout / DNS / TLS / hang: leave uncached, keep the emoji fallback.
        // Critically, do NOT block the UI waiting — this runs off the render path.
      }
    }

    try {
      client.close(force: true);
    } catch (_) {}

    await _saveIndex(d);
    if (missingChanged) await _saveMissing(d);
    debugPrint('[faces] wrote=$written missing=${_missing.length} cached=${_paths.length}');
    return written;
  }

  Future<void> _saveIndex(Directory d) async {
    try {
      File('${d.path}/$_indexName')
          .writeAsStringSync(jsonEncode(_paths), flush: true);
    } catch (_) {}
  }

  Future<void> _saveMissing(Directory d) async {
    try {
      File('${d.path}/$_missingName')
          .writeAsStringSync(jsonEncode(_missing.toList()), flush: true);
    } catch (_) {}
  }

  /// Stable filename for a URL. FNV-1a 64-bit rather than [String.hashCode],
  /// which is not guaranteed stable across process restarts.
  static String _safeName(String url) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(url)) {
      h ^= b;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return '${h.toUnsigned(64).toRadixString(16)}.png';
  }
}
