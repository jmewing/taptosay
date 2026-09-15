import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// On-device photo store for tile customization.
///
/// Photos live ONLY in the app's private documents directory
/// (`<app docs>/tiles/<category>/<label>.png`) — never in assets, never in
/// the repo, never uploaded anywhere. Each install personalizes its own
/// tiles for its own user.
///
/// A tiny JSON map (`tile_map.json`) records which tile has a photo and
/// where, so the app can rebuild paths after restarts.
class PhotoStore {
  PhotoStore._();
  static final PhotoStore instance = PhotoStore._();

  /// Bumped whenever a photo is added/removed so every open tile face
  /// rebuilds (ValueListenableBuilder in TileFace).
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Directory? _root;
  Map<String, String> _map = {}; // "Category|Label" -> relative path
  bool _loaded = false;

  Future<Directory> _dir() async {
    if (_root != null) return _root!;
    Directory tiles;
    try {
      final docs = await getApplicationDocumentsDirectory();
      tiles = Directory('${docs.path}/tiles');
      if (!tiles.existsSync()) tiles.createSync(recursive: true);
    } catch (_) {
      // No plugin available (e.g. widget tests): use a throwaway temp dir
      // so the app still renders. Photos just won't persist in that case.
      tiles = Directory.systemTemp.createTempSync('taptosay_tiles');
    }
    _root = tiles;
    return tiles;
  }

  String _key(String category, String label) => '$category|$label';

  String _safe(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_').trim().toLowerCase();

  /// Load the tile map (idempotent; call from main before building UI).
  Future<void> load() async {
    if (_loaded) return;
    final tiles = await _dir();
    final f = File('${tiles.path}/tile_map.json');
    if (f.existsSync()) {
      try {
        final decoded = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        _map = decoded.map((k, v) => MapEntry(k, v as String));
      } catch (_) {
        _map = {};
      }
    }
    _loaded = true;
  }

  /// Absolute path of the photo for a tile, or null if none is set.
  Future<String?> pathFor(String category, String label) async {
    await load();
    final rel = _map[_key(category, label)];
    if (rel == null) return null;
    final tiles = await _dir();
    final p = '${tiles.path}/$rel';
    return File(p).existsSync() ? p : null;
  }

  /// Whether the tile has a photo.
  Future<bool> hasPhoto(String category, String label) async =>
      await pathFor(category, label) != null;

  /// Copy a picked image into the store. Returns the stored absolute path.
  Future<String> setPhoto(String category, String label, String sourcePath) async {
    await load();
    final tiles = await _dir();
    final catDir = Directory('${tiles.path}/${_safe(category)}');
    if (!catDir.existsSync()) catDir.createSync(recursive: true);
    final dest = File('${catDir.path}/${_safe(label)}.png');
    final src = File(sourcePath);
    if (src.existsSync()) {
      src.copySync(dest.path);
    }
    _map[_key(category, label)] =
        '${_safe(category)}/${_safe(label)}.png';
    await _save();
    revision.value++;
    return dest.path;
  }

  /// Remove a tile's photo (no-op if none). Returns stored path or null.
  Future<String?> removePhoto(String category, String label) async {
    await load();
    final rel = _map.remove(_key(category, label));
    if (rel != null) {
      final tiles = await _dir();
      final f = File('${tiles.path}/$rel');
      if (f.existsSync()) f.deleteSync();
      await _save();
      revision.value++;
      return rel;
    }
    return null;
  }

  Future<void> _save() async {
    final tiles = await _dir();
    File('${tiles.path}/tile_map.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_map),
    );
  }

  /* ----- lost-result recovery (kiosk) -----
   * On the 2GB kiosk tablet the system picker can kill our activity, and
   * the picked photo would be lost. Before opening the picker we persist
   * WHICH tile is being edited; on next launch, retrieveLostData() (via
   * main) delivers the photo and we apply it here. */

  /// Remember which tile a pick is in flight for (survives process death).
  Future<void> markPending(String category, String label) async {
    final tiles = await _dir();
    File('${tiles.path}/pending_tile.txt')
        .writeAsStringSync('$category|$label');
  }

  /// Claim + clear the pending tile, or (null, null) if none.
  Future<(String?, String?)> takePending() async {
    final tiles = await _dir();
    final f = File('${tiles.path}/pending_tile.txt');
    if (!f.existsSync()) return (null, null);
    final parts = f.readAsStringSync().split('|');
    f.deleteSync();
    return (
      parts.isNotEmpty ? parts[0] : null,
      parts.length > 1 ? parts[1] : null,
    );
  }
}

/// Bridge to MainActivity: lift/restore kiosk lock-task so the system
/// camera app can open, then re-pin TapToSay. No-ops when not device owner.
class KioskBridge {
  static const _channel = MethodChannel('com.jmewing.taptosay/kiosk');

  /// Briefly stop lock-task (call right before launching the camera/gallery).
  static Future<void> lift() async {
    try {
      await _channel.invokeMethod('stopLockTask');
    } catch (_) {}
  }

  /// Re-engage lock-task (call after the picker returns).
  static Future<void> restore() async {
    try {
      await _channel.invokeMethod('startLockTask');
    } catch (_) {}
  }
}
