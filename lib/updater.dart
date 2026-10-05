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
