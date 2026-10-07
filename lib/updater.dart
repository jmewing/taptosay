import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// In-app self-update.
///
/// On launch the app asks the server for `download/latest.json` (the same
/// machine-readable manifest the website publishes). If the server advertises
/// a HIGHER versionCode than the one installed, the app offers to download
/// the APK and hand it to the Android installer.
///
/// This means a new build on the website reaches every tablet — the operator
/// never has to flash or re-install by hand.
class UpdateInfo {
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String? sha256;
  const UpdateInfo(this.versionName, this.versionCode, this.apkUrl, this.sha256);
}

/// An iOS update advertised by the App Store (Apple's public Lookup API).
/// Unlike Android there is nothing to download — the app can only offer to
/// open the store listing and let the user update from there.
class AppStoreUpdate {
  final String version;
  final String storeUrl;
  const AppStoreUpdate(this.version, this.storeUrl);
}

class Updater {
  static const MethodChannel _ch = MethodChannel('app.taptosay/kiosk');

  /// The installed versionCode, read from the native PackageManager.
  static Future<int> currentVersionCode() async {
    try {
      final v = await _ch.invokeMethod<Map<dynamic, dynamic>>('getAppVersion');
      return (v?['versionCode'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// The installed versionName (e.g. "1.1.6"), for the app-bar label.
  static Future<String> currentVersionName() async {
    try {
      final v = await _ch.invokeMethod<Map<dynamic, dynamic>>('getAppVersion');
      return (v?['versionName'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Ask the server for the latest build. Returns an [UpdateInfo] only when a
  /// strictly newer version is advertised; null when up to date or offline.
  ///
  /// Android only — iOS apps update through the App Store, so there is nothing
  /// to sideload there (and the platform channel has no installer on iOS).
  ///
  /// The manifest lives on the PUBLIC SITE host (`taptosay.app/download/`), not
  /// on the API host — the website and the QR both point there, so the app must
  /// read it from the same place.
  static const String _updateBase = 'https://taptosay.app';

  static Future<UpdateInfo?> check() async {
    if (!Platform.isAndroid) return null;
    final current = await currentVersionCode();
    if (current == 0) return null; // couldn't read our own version
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      try {
        final req =
            await client.getUrl(Uri.parse('$_updateBase/download/latest.json'));
        final res = await req.close();
        if (res.statusCode != 200) return null;
        final body = await res.transform(utf8.decoder).join();
        final j = jsonDecode(body) as Map<String, dynamic>;
        final code = (j['versionCode'] as num?)?.toInt() ?? 0;
        final name = (j['versionName'] ?? '').toString();
        final apk = (j['apk'] ?? '').toString();
        if (code > current && apk.isNotEmpty) {
          return UpdateInfo(name, code, apk, j['apk_sha256']?.toString());
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      // offline / DNS blocked — updates are best-effort, never block the app
    }
    return null;
  }

  /// The app's bundle id, used to ask Apple which version is live on the App
  /// Store. Must match ios/Runner.xcodeproj PRODUCT_BUNDLE_IDENTIFIER.
  static const String _iosBundleId = 'app.taptosay';

  /// Ask the App Store whether a newer version is published. Returns an
  /// [AppStoreUpdate] only when the STORE version is strictly newer than the
  /// installed one; null when up to date, not yet published, or offline.
  ///
  /// iOS only — Android self-updates from the website (see [check]). Before
  /// 1.0 is approved the Lookup API returns zero results, so this quietly does
  /// nothing; it starts working the moment the app goes live, with no rebuild.
  static Future<AppStoreUpdate?> checkAppStore() async {
    if (!Platform.isIOS) return null;
    final current = await currentVersionName();
    if (current.isEmpty) return null; // couldn't read our own version
    try {
      final client =
          HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final req = await client.getUrl(Uri.parse(
            'https://itunes.apple.com/lookup?bundleId=$_iosBundleId'));
        final res = await req.close();
        if (res.statusCode != 200) return null;
        final body = await res.transform(utf8.decoder).join();
        final j = jsonDecode(body) as Map<String, dynamic>;
        final results = (j['results'] as List?) ?? const [];
        if (results.isEmpty) return null; // not live on the store yet
        final r = results.first as Map<String, dynamic>;
        final storeVersion = (r['version'] ?? '').toString();
        final url = (r['trackViewUrl'] ?? '').toString();
        if (storeVersion.isEmpty || url.isEmpty) return null;
        if (_isNewer(storeVersion, current)) {
          return AppStoreUpdate(storeVersion, url);
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      // offline / DNS blocked — best-effort, never block the app
    }
    return null;
  }

  /// True when dotted-numeric version [a] is strictly newer than [b]
  /// (e.g. "1.1.7" > "1.1.6", "1.2" > "1.1.9"). Missing components count as 0.
  static bool _isNewer(String a, String b) {
    List<int> parts(String v) => v
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Open a URL (the App Store listing) in the system browser / store app.
  /// Returns true if the platform reported it opened.
  static Future<bool> openStore(String url) async {
    try {
      final ok = await _ch.invokeMethod<bool>('openUrl', {'url': url});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Download the advertised APK and hand it to the system installer.
  /// Returns true if the installer was launched.
  static Future<bool> downloadAndInstall(UpdateInfo info) async {
    try {
      final dir = await getTemporaryDirectory();
      final upd = Directory('${dir.path}/updates');
      if (!upd.existsSync()) upd.createSync(recursive: true);
      final file = File('${upd.path}/taptosay-${info.versionName}.apk');

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        final req = await client.getUrl(Uri.parse(info.apkUrl));
        final res = await req.close();
        if (res.statusCode != 200) return false;
        final sink = file.openWrite();
        await res.pipe(sink);
        await sink.close();
      } finally {
        client.close(force: true);
      }

      final ok = await _ch.invokeMethod<bool>('installApk', {'path': file.path});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
