import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;
import 'package:path_provider/path_provider.dart';

import 'vocab.dart';

/// Tablet-facing config sync.
///
/// The tablet holds four remote credentials — school (TEA campus) ID,
/// student ID, auth password, and server URL — plus the current
/// settings/exit PINs. On launch it POSTs those to `/api/config/sync` and
/// the server returns the config + freshly-rotated PINs. Everything is
/// cached on-device so the tablet works offline; if there is no cache the
/// app falls back to its built-in vocabulary.
class ConfigStore {
  ConfigStore._();
  static final ConfigStore instance = ConfigStore._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Directory? _root;
  bool _loaded = false;

  // Provisioning
  String? _schoolId;
  String? _studentId;
  String? _authPassword;
  String? _serverUrl;

  /// Public defaults. The primary is the DNS name; [fallbackServerUrls] adds the
  /// same host by raw IP:port, so a network that blocks or cannot resolve DNS
  /// can still reach the API. Never a LAN address — a tablet that leaves the
  /// building must still sync.
  static const String defaultServerUrl = 'https://api.taptosay.app';
  static const List<String> fallbackServerUrls = <String>[
    'https://api.taptosay.app',
    'http://129.121.137.182:8088',
  ];

  /// True for hosts that only work on a local network — adopting or defaulting to
  /// one of these is what strands a shipped tablet.
  static bool isPrivateHost(String url) {
    final u = url.trim().toLowerCase();
    return u.contains('localhost') ||
        u.contains('127.0.0.1') ||
        u.contains('192.168.') ||
        u.contains('10.') ||
        u.contains('172.16.') ||
        u.contains('172.17.') ||
        u.contains('172.18.') ||
        u.contains('172.19.') ||
        u.contains('172.2') ||
        u.contains('172.30.') ||
        u.contains('172.31.') ||
        u.contains('.local');
  }

  // Cached result
  List<Category>? _cachedCategories;
  String? _settingsPin;
  String? _exitPin;
  DateTime? _lastSyncAt;

  Future<Directory> _dir() async {
    if (_root != null) return _root!;
    Directory d;
    try {
      final docs = await getApplicationDocumentsDirectory();
      d = Directory('${docs.path}/sync');
      if (!d.existsSync()) d.createSync(recursive: true);
    } catch (_) {
      d = Directory.systemTemp.createTempSync('taptosay_sync');
    }
    _root = d;
    return d;
  }

  File _cfgFile(Directory d) => File('${d.path}/config.json');

  Future<void> load() async {
    if (_loaded) return;
    final d = await _dir();
    final f = _cfgFile(d);
    if (f.existsSync()) {
      try {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        _schoolId = j['school_id'] as String?;
        _studentId = j['student_id'] as String?;
        _authPassword = j['auth_password'] as String?;
        _serverUrl = j['server_url'] as String?;
        // Self-heal a URL that can no longer work. Older builds/QRs baked in a
        // LAN address (e.g. http://192.168.12.5:8088); a tablet that has left
        // that network would otherwise retry a dead host forever and never
        // sync. Promote it to the public default instead of trusting the cache.
        if (_serverUrl != null && isPrivateHost(_serverUrl!)) {
          _serverUrl = defaultServerUrl;
        }
        _settingsPin = j['settings_pin'] as String?;
        _exitPin = j['exit_pin'] as String?;
        final raw = j['last_sync_at'] as String?;
        _lastSyncAt = raw == null ? null : DateTime.tryParse(raw);
        final cats = j['categories'] as List?;
        if (cats != null) {
          _cachedCategories = cats
              .map((e) => Category.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {
        // corrupt cache — ignore, will re-provision or fall back
      }
    }
    _loaded = true;
  }

  bool get isProvisioned =>
      _schoolId != null && _studentId != null && _authPassword != null && _serverUrl != null;

  /// Candidate base URLs to try, in order: the configured/pooled server first,
  /// then the public fallbacks. De-duplicated, and the plain-HTTP IP fallback
  /// is skipped whenever the primary is already an HTTPS host (nothing to gain
  /// by downgrading transport on a working network).
  List<String> get _serverCandidates {
    final out = <String>[];
    final primary = _serverUrl?.replaceAll(RegExp(r'/+$'), '');
    if (primary != null && primary.isNotEmpty) out.add(primary);
    for (final f in fallbackServerUrls) {
      final u = f.replaceAll(RegExp(r'/+$'), '');
      if (out.contains(u)) continue;
      out.add(u);
    }
    return out;
  }

  String? get schoolId => _schoolId;
  String? get studentId => _studentId;
  String? get authPassword => _authPassword;
  String? get serverUrl => _serverUrl;

  /// PINs: only the server's synced value. Never fall back to a hardcoded
  /// default — if the device has not synced yet, the PIN is empty and the
  /// Exit action reports it as unconfigured instead of accepting a preset.
  String get settingsPin => _settingsPin ?? '';
  String get exitPin => _exitPin ?? '';

  /// Categories: cached, else built-in fallback.
  List<Category> get categories => _cachedCategories ?? builtInCategories;

  DateTime? get lastSyncAt => _lastSyncAt;

  /// Absolute URL for an uploaded custom photo (media_id). Requires provisioning
  /// creds (the tablet authenticates to the media endpoint the same way it
  /// authenticates to sync). Returns null when not provisioned.
  String? mediaUrl(int? mediaId) {
    if (mediaId == null || mediaId <= 0) return null;
    if (_serverUrl == null) return null;
    final base = _serverUrl!.replaceAll(RegExp(r'/+$'), '');
    return '$base/api/media/$mediaId?school_id=$_schoolId&student_id=$_studentId&auth_password=$_authPassword';
  }

  /// Absolute URL for a Mulberry AAC symbol PNG (static set served by the API).
  String? symbolUrl(String? symbol) {
    if (symbol == null || symbol.isEmpty) return null;
    if (_serverUrl == null) return null;
    final base = _serverUrl!.replaceAll(RegExp(r'/+$'), '');
    final name = Uri.encodeComponent(symbol);
    return '$base/mulberry/$name.png';
  }

  /// Save the four provisioning details (first-run setup).
  Future<void> provision({
    required String schoolId,
    required String studentId,
    required String authPassword,
    required String serverUrl,
  }) async {
    _schoolId = schoolId.trim();
    _studentId = studentId.trim();
    _authPassword = authPassword;
    _serverUrl = _normalize(serverUrl.trim());
    await _save();
  }

  /// Apply the admin-extras bundle delivered during device-owner QR/NFC
  /// provisioning (keys: server_url, student_id, school_tea_id, auth_password).
  /// Returns true if enough fields were present to mark the tablet provisioned.
  Future<bool> applyProvisioningExtras(Map<String, String> extras) async {
    final school = (extras['school_tea_id'] ?? extras['school_id'] ?? '').trim();
    final student = (extras['student_id'] ?? '').trim();
    final auth = (extras['auth_password'] ?? '');
    final url = (extras['server_url'] ?? '').trim();
    if (school.isEmpty || student.isEmpty || auth.isEmpty || url.isEmpty) {
      return false;
    }
    await provision(
      schoolId: school,
      studentId: student,
      authPassword: auth,
      serverUrl: url,
    );
    return true;
  }

  String _normalize(String url) {
    var s = url.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      // LAN / local installs are always plain HTTP (no TLS yet). Defaulting to
      // https:// here makes the client fail with WRONG_VERSION_NUMBER.
      s = 'http://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Future<void> _save() async {
    final d = await _dir();
    _cfgFile(d).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'school_id': _schoolId,
        'student_id': _studentId,
        'auth_password': _authPassword,
        'server_url': _serverUrl,
        'settings_pin': _settingsPin,
        'exit_pin': _exitPin,
        'last_sync_at': _lastSyncAt?.toIso8601String(),
        'categories': _cachedCategories == null
            ? null
            : [
                for (final c in _cachedCategories!)
                  {
                    'name': c.name,
                    'emoji': c.emoji,
                    if (c.symbol != null) 'symbol': c.symbol,
                    if (c.mediaId != null) 'media_id': c.mediaId,
                    'color': '#${c.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
                    'sayings': [
                      for (final s in c.sayings)
                        {
                          'label': s.label,
                          'emoji': s.emoji,
                          if (s.symbol != null) 'symbol': s.symbol,
                          if (s.mediaId != null) 'media_id': s.mediaId,
                          'color': '#${s.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
                          if (s.subTitle != null) 'subTitle': s.subTitle,
                          if (s.sub != null)
                            'sub': [
                              for (final d in s.sub!)
                                {
                                  'label': d.label,
                                  'emoji': d.emoji,
                                  if (d.symbol != null) 'symbol': d.symbol,
                                  if (d.mediaId != null) 'media_id': d.mediaId,
                                  'color': '#${d.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
                                }
                            ],
                        }
                    ],
                  }
              ],
      }),
    );
    revision.value++;
  }

  /// POST /api/config/sync. Tries the configured server, then the public
  /// fallbacks (the same API by raw IP:port) so a network that cannot resolve
  /// DNS still syncs. Returns parsed categories on success.
  /// Throws [SyncException] with a user-facing message on failure.
  Future<List<Category>> sync() async {
    await load();
    if (!isProvisioned) {
      throw const SyncException('Not provisioned yet');
    }
    final candidates = _serverCandidates;
    String? lastMsg;

    for (var i = 0; i < candidates.length; i++) {
      final base = candidates[i];
      final isLast = i == candidates.length - 1;
      String? failure;
      try {
        final j = await _postSync(base);
        // Success: adopt the server's own identity as the saved URL when it
        // offers one, so the tablet converges on the pooled host afterwards.
        final echoed = (j['server_url'] as String?)?.trim();
        final adopt = (echoed != null && echoed.isNotEmpty && !isPrivateHost(echoed))
            ? _normalize(echoed)
            : base;
        await _applySyncResult(j, adopt);
        return categories;
      } on SyncException catch (e) {
        failure = e.message;
        lastMsg = e.message;
      } catch (e) {
        failure = e.toString();
        lastMsg = e.toString();
      }
      // A credentials/permission rejection is the same on every host — retrying
      // just delays the error the user needs to see.
      if (!_isRetriable(failure)) {
        throw SyncException(failure);
      }
      if (isLast) {
        debugPrint('sync: all ${candidates.length} candidate(s) failed; last=$failure');
      }
    }
    throw SyncException(lastMsg ?? 'Sync failed');
  }

  /// A connection-level problem is worth retrying on the fallback host; an
  /// HTTP/credential rejection is not.
  static bool _isRetriable(String msg) {
    final m = msg.toLowerCase();
    return m.contains('socketexception') ||
        m.contains('failed host lookup') ||
        m.contains('connection') ||
        m.contains('timed out') ||
        m.contains('timeout') ||
        m.contains('handshake') ||
        m.contains('network is unreachable') ||
        m.contains('nodename nor servname') ||
        m.contains('no address associated');
  }

  /// One POST to [base]; returns the decoded JSON or throws [SyncException].
  Future<Map<String, dynamic>> _postSync(String base) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse('$base/api/config/sync');
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'school_id': _schoolId,
        'student_id': _studentId,
        'auth_password': _authPassword,
      }));

      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();

      if (res.statusCode != 200) {
        String msg;
        try {
          msg = (jsonDecode(body) as Map)['error'] as String? ?? 'HTTP ${res.statusCode}';
        } catch (_) {
          msg = 'HTTP ${res.statusCode}';
        }
        throw SyncException(msg);
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  /// Apply a successful sync payload and persist, adopting [adoptedUrl].
  Future<void> _applySyncResult(Map<String, dynamic> j, String adoptedUrl) async {
    final config = j['config'] as Map<String, dynamic>?;
    final catsRaw = config?['categories'] as List?;
    final cats = catsRaw
            ?.map((e) => Category.fromJson(e as Map<String, dynamic>))
            .toList() ??
        builtInCategories;

    _serverUrl = adoptedUrl;
    _cachedCategories = cats;
    _settingsPin = j['settings_pin'] as String? ?? _settingsPin;
    _exitPin = j['exit_pin'] as String? ?? _exitPin;
    _lastSyncAt = DateTime.now();
    await _save();
  }
}

class SyncException implements Exception {
  final String message;
  const SyncException(this.message);
  @override
  String toString() => message;
}
